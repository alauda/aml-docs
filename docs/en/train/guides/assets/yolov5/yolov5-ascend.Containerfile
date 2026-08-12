ARG BASE_IMAGE
FROM ${BASE_IMAGE}

USER 0
RUN pip install --no-cache-dir \
      fastapi==0.115.6 \
      "uvicorn[standard]==0.34.0"

COPY --chown=1000:1000 yolov5_ascend_server.py /opt/yolov5/serve.py
RUN chmod 0555 /opt/yolov5/serve.py

USER 1000
