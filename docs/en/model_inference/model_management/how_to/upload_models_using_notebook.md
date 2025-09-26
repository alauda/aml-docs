# Uploading a Model Using Workbench/Notebook

Uploading a model to the model repository is the first step for publishing the LLM inference service and creating fine-tuning tasks. Using Workbench/Notebook is recommended. Since Workbench/Notebook instances run on the platform, they offer optimal upload speeds. Notebooks also have a built-in `git lfs` tool ([git lfs](https://git-lfs.com/)), so installing it locally is not needed.

## Creating a Workbench/Notebook Instance

> **Note:** In versions of Alauda AI >= 1.4, you can create a Notebook instance using "Workbench" in the left navigation. In versions of Alauda AI <= 1.3, you can create a Notebook instance using "Advanced - Notebook".

The detailed workbench/notebook creation instructions are not detailed here. Please refer to workbench docs.
You need to note that sufficient storage space must be created to store the model file for the upload process to complete successfully.

## Preparing the Model

Download the required model from any open source community. We recommend downloading from the following three websites, such as [https://hf-mirror.com/deepseek-ai/DeepSeek-R1].

* [https://huggingface.co/](https://huggingface.co/)
* [https://hf-mirror.com](https://hf-mirror.com)
* [https://modelscope.cn/home](https://modelscope.cn/home)

When downloading models from huggingface or hf-mirror, you can use the `huggingface-cli` command (requires `pip install huggingface_hub` ). For more command line usage instructions, please refer to [https://hf-mirror.com](https://hf-mirror.com). Sample download command to download model `DeepSeek-R1-Distill-Qwen-1.5B`:

```bash
export HF_ENDPOINT=https://hf-mirror.com
pip install huggingface_hub
huggingface-cli download --resume-download deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B --local-dir DeepSeek-R1-Distill-Qwen-1.5B
```

> **Note:** If your environment doesn't have internet access, you can choose find a suitable machine with internet access (such as a desktop or server with a high-speed connection to the cluster), download the model, and then copy it to the Notebook environment.

## Create a Model Repository

Open and log in to Alauda AI. On the "Model Repository" page, click "Create Model Repository." Enter the parameters in order and click "Create."

* Name: Any. We recommend using the downloaded model name. In this example, we use "DeepSeek-R1-Distill-Qwen-1.5B".
* Tag: Any. We recommend entering the model category for easier searching, such as "deepseek."
* Description: Any.

After the model repository is created, you can find the model's "Repository Address" on the "Details" page. This will be used for subsequent git builds. Use when pushing

## Uploading the model

> **Note:** Before beginning, ensure Git and Git LFS are installed in your Notebook environment: `git lfs install && git lfs version`

In Notebook, open Terminal and execute the following command to push the model file to the model repository.

```bash
# Navigate to the folder where you downloaded the model in the previous step.
cd <your-repo-name>
# Delete the previous Git repository information for the model (if any).
rm -rf .git
# Initialization Create a git repository and set the push URL to the model repository created in the previous step.
git init
git checkout -b main
git remote add origin <repository-url>

# In the .gitattributes file, specify the file types to tell Git LFS which files to track.
# The following file identifies common model file formats and can be used directly.

cat >.gitattributes <<EOL
*.7z filter=lfs diff=lfs merge=lfs -text
*.arrow filter=lfs diff=lfs merge=lfs -text
*.bin filter=lfs diff=lfs merge=lfs -text
*.bz2 filter=lfs diff=lfs merge=lfs -text
*.ckpt filter=lfs diff=lfs merge=lfs -text
*.ftz filter=lfs diff=lfs merge=lfs -text
*.gz filter=lfs diff=lfs merge=lfs -text
*.h5 filter=lfs diff=lfs merge=lfs -text
*.joblib filter=lfs diff=lfs merge=lfs -text
*.lfs.* filter=lfs diff=lfs merge=lfs -text
*.mlmodel filter=lfs diff=lfs merge=lfs -text
*.model filter=lfs diff=lfs merge=lfs -text
*.msgpack filter=lfs diff=lfs merge=lfs -text
*.npy filter=lfs diff=lfs merge=lfs -text
*.npz filter=lfs diff=lfs merge=lfs -text
*.onnx filter=lfs diff=lfs merge=lfs -text
*.ot filter=lfs diff=lfs merge=lfs -text
*.parquet filter=lfs diff=lfs merge=lfs -text
*.pb filter=lfs diff=lfs merge=lfs -text
*.pickle filter=lfs diff=lfs merge=lfs -text
*.pkl filter=lfs diff=lfs merge=lfs -text
*.pt filter=lfs diff=lfs merge=lfs -text
*.pth filter=lfs diff=lfs merge=lfs -text
*.rar filter=lfs diff=lfs merge=lfs -text
*.safetensors filter=lfs diff=lfs merge=lfs -text
saved_model/**/* filter=lfs diff=lfs merge=lfs -text
*.tar.* filter=lfs diff=lfs merge=lfs -text
*.tar filter=lfs diff=lfs merge=lfs -text
*.tflite filter=lfs diff=lfs merge=lfs -text
*.tgz filter=lfs diff=lfs merge=lfs -text
*.wasm filter=lfs diff=lfs merge=lfs -text
*.xz filter=lfs diff=lfs merge=lfs -text
*.zip filter=lfs diff=lfs merge=lfs -text
*.zst filter=lfs diff=lfs merge=lfs -text
*tfevents* filter=lfs diff=lfs merge=lfs -text
EOL

# You can also add or modify manually .gitattributes file, for example:
# Track files with the specified suffix
git lfs track "*.h5" "*.bin" "*.pt"

# Add all changes, including the .gitattributes file (if created) and the model files
git add .
# Ensure all files that conform to LFS rules are correctly marked
git add --renormalize .

# Check the list of files currently tracked by LFS (optional)
# If larger model files you wish to store using LFS are not listed here, verify that the above command was executed correctly
git lfs ls-files -n

# Commit changes
# It is recommended to configure your username and email address, or ensure they are configured globally
# git config --global user.name "Your Name"
# git config --global user.email "your.email@example.com"
git commit -am "Add LLM model files with Git LFS"

# Push to the remote repository
git -c http.sslVerify=false -c lfs.activitytimeout=36000 push -u origin main

# If you need to force a push, for example after using git lfs migrate --import:
# git push -u origin main --force
```

## Editing Model Metadata

Open the "Model Details" page, go to the "File Management" tab, click "Edit Metadata",  select the "task type" and "framework" metadata based on the uploaded model, and then click "Confirm."

> **Note:** Only after configuring the task type and framework metadata can you use the "Publish Inference Service" page to publish the inference service. For more information about model task types, refer to [Huggingface pipelines](https://huggingface.co/docs/transformers/en/main_classes/pipelines)


## Appendix

### Marking LFS files based on file size

The `git lfs migrate` command can help you find and migrate large files that already exist in your Git history but are not tracked by LFS. Please note that this command rewrites your commit history. If your repository is shared, be sure to coordinate with your collaborators and use `--force` when pushing.

Checking the files that need to be migrated

```bash
git lfs migrate info
```

Migrate existing large files to LFS:

The following command will migrate all files larger than 100MB to Git LFS. This 100MB limit is based on GitHub's recommended file size limit for optimal performance.

```bash
git lfs migrate import --above 100MB
```

If your repository is shared, be sure to notify all collaborators before running this command and be prepared to use `git push --force` when pushing.