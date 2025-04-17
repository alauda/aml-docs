#!/bin/bash

count=1
max_retries=99  # 与原始脚本的 99 次保持一致

while :
do
    # 执行翻译命令并捕获退出状态
    yarn translate -s en -t zh -g '*' --copy
    exit_code=$?

    # 成功执行时退出循环
    if [ $exit_code -eq 0 ]; then
        echo "✅ 翻译成功完成"
        break
    fi

    # 达到最大重试次数时退出
    if [ $count -ge $max_retries ]; then
        echo "❌ 已重试 $max_retries 次仍失败，请检查问题"
        break
    fi

    # 失败时执行重试逻辑
    echo "⚠️ 第 $count 次失败，75秒后重试..."
    sleep 75
    ((count++))
done
