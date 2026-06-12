buildctl \
--addr tcp://192.168.142.83:1234 build \
--frontend dockerfile.v0 \
--local context=$PWD \
--local dockerfile=$PWD \
--opt filename=fine_tune_with_llamafactory_npu.Containerfile \
--opt platform=linux/arm64 \
--opt build-arg:INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple \
--output type=image,name=build-harbor.alauda.cn/mlops/fine_tune_with_llamafactory_npu:v0.9.4-cann_8.5.0-torch_2.6.0-v2,push=true

