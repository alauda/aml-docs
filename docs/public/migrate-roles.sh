#!/usr/bin/env bash

set -euo pipefail

# Run this script against the global cluster. It migrates the selected cluster's
# legacy UserBindings to namespace RoleBindings in the selected cluster.
#
# Required tools: kubectl, base64, sed, awk, and either shasum or sha256sum.
# The script intentionally does not require jq or yq.
#
# Environment variables:
#   KUBECTL           kubectl executable (default: kubectl)
#   DRY_RUN           print manifests without changing the target cluster (default: false)
#
# Command options:
#   --keep-source         keep source UserBindings after migration
#   --backup-dir DIR      directory for source UserBinding backups

kubectl_bin="${KUBECTL:-kubectl}"
dry_run="${DRY_RUN:-false}"
delete_source="true"
backup_dir=""
source_namespace="cpaas-system"

cluster_name=""
target_kubeconfig=""
declare -a migrated_sources=()

auto_backup_dir() {
  printf '%s/migrate-roles-backup' "$(pwd)"
}

usage() {
  cat <<'EOF'
Usage:
  migrate-roles.sh [options] <cluster-name>

Migrates AML namespace UserBindings from the global cluster to namespace
RoleBindings in <cluster-name>.

By default source UserBindings are backed up and deleted after successful
migration. Use --keep-source to retain them. DRY_RUN=true prints manifests
without writing them or deleting source resources.

Options:
  --keep-source         keep source UserBindings after migration
  --backup-dir DIR      directory for source UserBinding backups; when omitted,
                        ./migrate-roles-backup is created automatically
  -h, --help            show this help
EOF
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required"
}

trim() {
  printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

base64_decode() {
  if base64 --decode </dev/null >/dev/null 2>&1; then
    base64 --decode
  else
    base64 -D
  fi
}

sha256_prefix() {
  local namespace="$1"
  local user="$2"
  local cluster_role="$3"

  if command -v shasum >/dev/null 2>&1; then
    printf '%s\0%s\0%s' "$namespace" "$user" "$cluster_role" \
      | shasum -a 256 | awk '{print substr($1, 1, 6)}'
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s\0%s\0%s' "$namespace" "$user" "$cluster_role" \
      | sha256sum | awk '{print substr($1, 1, 6)}'
  else
    fail 'shasum or sha256sum is required'
  fi
}

global_kubectl() {
  "$kubectl_bin" "$@"
}

target_kubectl() {
  "$kubectl_bin" --kubeconfig "$target_kubeconfig" "$@"
}

safe_role_binding_user() {
  local user="$1"
  local safe

  safe="$(printf '%s' "$user" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  safe="${safe:0:32}"
  safe="$(printf '%s' "$safe" | sed -E 's/-+$//')"
  if [[ -z "$safe" ]]; then
    safe="u"
  fi
  printf '%s' "$safe"
}

role_binding_name() {
  local role="$1"
  local namespace="$2"
  local user="$3"
  local cluster_role="aml-namespace-${role}:namespaced-scope"
  local safe_user
  local suffix

  safe_user="$(safe_role_binding_user "$user")"
  suffix="$(sha256_prefix "$namespace" "$user" "$cluster_role")"
  printf 'aml-%s-%s-%s' "$role" "$safe_user" "$suffix"
}

yaml_quote() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf "'%s'" "$value"
}

role_binding_manifest() {
  local name="$1"
  local namespace="$2"
  local role="$3"
  local user="$4"
  local cluster_role="aml-namespace-${role}:namespaced-scope"

  cat <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $(yaml_quote "$name")
  namespace: $(yaml_quote "$namespace")
  labels:
    aml.cpaas.io/namespace-role-binding: 'true'
    aml.cpaas.io/role: $(yaml_quote "$role")
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: $(yaml_quote "$cluster_role")
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: $(yaml_quote "$user")
EOF
}

has_equivalent_role_binding() {
  local namespace="$1"
  local cluster_role="$2"
  local user="$3"
  local binding
  local role_bindings
  local role_ref
  local kind
  local name
  local subject
  local subject_kind
  local subjects

  role_bindings="$(target_kubectl get rolebindings -n "$namespace" -o name)"
  while IFS= read -r binding; do
    [[ -z "$binding" ]] && continue

    role_ref="$(target_kubectl get "$binding" -n "$namespace" \
      -o 'jsonpath={.roleRef.kind}{"\t"}{.roleRef.name}')"
    IFS=$'\t' read -r kind name <<<"$role_ref"
    [[ "$kind" == 'ClusterRole' && "$name" == "$cluster_role" ]] || continue

    subjects="$(target_kubectl get "$binding" -n "$namespace" \
      -o 'jsonpath={range .subjects[*]}{.kind}{"\t"}{.name}{"\n"}{end}')"
    while IFS=$'\t' read -r subject_kind subject; do
      if [[ "$subject_kind" == 'User' && "$subject" == "$user" ]]; then
        return 0
      fi
    done <<<"$subjects"
  done <<<"$role_bindings"
  return 1
}

create_role_binding() {
  local name="$1"
  local namespace="$2"
  local role="$3"
  local user="$4"
  local cluster_role="aml-namespace-${role}:namespaced-scope"
  local manifest

  if has_equivalent_role_binding "$namespace" "$cluster_role" "$user"; then
    printf 'skip: %s/%s already grants %s to %s\n' "$namespace" "$name" "$role" "$user"
    return 0
  fi

  manifest="$(role_binding_manifest "$name" "$namespace" "$role" "$user")"
  if [[ "$dry_run" == 'true' ]]; then
    printf 'dry-run: create %s/%s for %s\n%s\n' "$namespace" "$name" "$user" "$manifest"
    return 0
  fi

  if printf '%s\n' "$manifest" | target_kubectl apply -f -; then
    printf 'created: %s/%s for %s\n' "$namespace" "$name" "$user"
    return 0
  fi

  # A concurrent run may have created the same binding. Only treat that as
  # success when the resulting object is equivalent to the requested grant.
  if has_equivalent_role_binding "$namespace" "$cluster_role" "$user"; then
    printf 'skip: %s/%s was created concurrently for %s\n' "$namespace" "$name" "$user"
    return 0
  fi
  return 1
}

load_target_kubeconfig() {
  local encoded

  encoded="$(global_kubectl get secret "${cluster_name}-kubeconfig" -n "$source_namespace" \
    -o 'jsonpath={.data.value}')" || fail "cannot read ${source_namespace}/${cluster_name}-kubeconfig from the global cluster"
  [[ -n "$encoded" ]] || fail "Secret ${source_namespace}/${cluster_name}-kubeconfig has no data.value"

  target_kubeconfig="$(mktemp "${TMPDIR:-/tmp}/migrate-roles.XXXXXX")"
  if ! printf '%s' "$encoded" | base64_decode >"$target_kubeconfig"; then
    fail "cannot decode ${source_namespace}/${cluster_name}-kubeconfig"
  fi
  chmod 600 "$target_kubeconfig"
  trap 'rm -f "$target_kubeconfig"' EXIT

  target_kubectl version --request-timeout=15s >/dev/null 2>&1 \
    || fail "cannot connect to target cluster ${cluster_name}"
}

backup_source_binding() {
  local name="$1"
  local backup_file="$backup_dir/${name}.yaml"

  global_kubectl get userbindings.auth.alauda.io "$name" -o yaml >"$backup_file" \
    || fail "cannot back up UserBinding ${name}"
  printf 'backup: %s\n' "$backup_file"
}

migrate_bindings() {
  local records
  local name
  local role_ref
  local cluster
  local constraint_namespace
  local label_namespace
  local scope
  local user
  local role
  local namespace
  local binding_name

  records="$(global_kubectl get userbindings.auth.alauda.io \
    -o 'jsonpath={range .items[*]}{.metadata.name}{"\t"}{.spec.roleRef}{"\t"}{.spec.constraint[0].cluster}{"\t"}{.spec.constraint[0].namespace}{"\t"}{.metadata.labels.cpaas\.io/namespace}{"\t"}{.spec.scope}{"\t"}{.metadata.annotations.auth\.cpaas\.io/user\.email}{"\n"}{end}')" \
    || fail 'cannot list auth.alauda.io/v1 UserBindings from the global cluster'

  while IFS=$'\t' read -r name role_ref cluster constraint_namespace label_namespace scope user; do
    [[ -z "$name" ]] && continue

    role_ref="$(trim "$role_ref")"
    cluster="$(trim "$cluster")"
    constraint_namespace="$(trim "$constraint_namespace")"
    label_namespace="$(trim "$label_namespace")"
    scope="$(trim "$scope")"
    user="$(trim "$user")"

    case "$role_ref" in
      aml-namespace-owner) role='owner' ;;
      aml-namespace-editor) role='editor' ;;
      aml-namespace-viewer) role='viewer' ;;
      *) continue ;;
    esac

    if [[ "$cluster" != "$cluster_name" ]]; then
      continue
    fi
    if [[ -n "$scope" && "$scope" != 'namespace' ]]; then
      printf 'warning: skip UserBinding %s with unsupported scope %s\n' "$name" "$scope" >&2
      continue
    fi

    namespace="$constraint_namespace"
    if [[ -z "$namespace" ]]; then
      namespace="$label_namespace"
    fi
    if [[ -z "$namespace" || -z "$user" ]]; then
      printf 'warning: skip incomplete UserBinding %s\n' "$name" >&2
      continue
    fi

    binding_name="$(role_binding_name "$role" "$namespace" "$user")"
    printf 'migrate: UserBinding %s -> %s/%s (%s, %s)\n' \
      "$name" "$namespace" "$binding_name" "$role" "$user"
    create_role_binding "$binding_name" "$namespace" "$role" "$user" \
      || fail "cannot create RoleBinding ${namespace}/${binding_name} for UserBinding ${name}"
    migrated_sources+=("$name")
  done <<<"$records"
}

backup_and_delete_migrated_sources() {
  local name

  [[ "$delete_source" == 'true' ]] || return 0
  [[ "$dry_run" == 'true' ]] && {
    printf 'dry-run: would back up and delete %d UserBinding(s)\n' "${#migrated_sources[@]}"
    return 0
  }

  mkdir -p "$backup_dir"
  [[ -d "$backup_dir" && -w "$backup_dir" ]] || fail "backup directory is not writable: $backup_dir"
  printf 'backing up and deleting %d successfully migrated UserBinding(s)\n' "${#migrated_sources[@]}"
  for name in "${migrated_sources[@]}"; do
    backup_source_binding "$name"
    global_kubectl delete userbindings.auth.alauda.io "$name"
  done
}

parse_args() {
  local arg

  while (($# > 0)); do
    arg="$1"
    case "$arg" in
      --keep-source)
        delete_source='false'
        shift
        ;;
      --backup-dir)
        (($# >= 2)) || fail '--backup-dir requires a directory'
        backup_dir="$2"
        shift 2
        ;;
      --backup-dir=*)
        backup_dir="${arg#*=}"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -* )
        fail "unknown option: $arg"
        ;;
      *)
        [[ -z "$cluster_name" ]] || fail "unexpected argument: $arg"
        cluster_name="$arg"
        shift
        ;;
    esac
  done

  if (($# > 0)); then
    [[ -z "$cluster_name" ]] || fail "unexpected argument: $1"
    cluster_name="$1"
    shift
  fi
  [[ -n "$cluster_name" ]] || { usage >&2; exit 1; }
}

main() {
  parse_args "$@"

  require_command "$kubectl_bin"
  require_command base64
  require_command sed
  require_command awk
  require_command tr
  if ! command -v shasum >/dev/null 2>&1 && ! command -v sha256sum >/dev/null 2>&1; then
    fail 'shasum or sha256sum is required'
  fi

  [[ "$dry_run" == 'true' || "$dry_run" == 'false' ]] \
    || fail 'DRY_RUN must be true or false'
  if [[ "$delete_source" == 'true' && -z "$backup_dir" ]]; then
    backup_dir="$(auto_backup_dir)"
  fi
  if [[ "$delete_source" == 'false' && -n "$backup_dir" ]]; then
    printf 'warning: --backup-dir is ignored with --keep-source\n' >&2
  fi

  load_target_kubeconfig
  migrate_bindings
  backup_and_delete_migrated_sources
}

main "$@"
