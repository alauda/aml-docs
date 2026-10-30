ARG BASE_IMAGE
FROM ${BASE_IMAGE}

USER 0
RUN python3 -m pip install --no-cache-dir \
      fastapi==0.115.6 \
      "uvicorn[standard]==0.34.0" \
      numpy==1.26.4

COPY --chown=1000:1000 yolov5_ascendcl_om_server.py /opt/yolov5/ascendcl_om_server.py
RUN chmod 0555 /opt/yolov5/ascendcl_om_server.py

HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD python3 -c "from urllib.request import urlopen; urlopen('http://127.0.0.1:8080/v2/health/ready', timeout=2)" || exit 1

USER 1000
