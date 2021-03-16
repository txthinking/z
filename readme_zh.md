# Boa

[English](readme.md)

Boa可以添加开机自动命令

### 用 [nami](https://github.com/txthinking/nami) 安装

```
$ nami install github.com/brook-community/boa
```

### 使用

	boa: auto start command at boot

        <command>   add a command
        list        show added commands
        remove <id> remove a command

        help        show help
        version     show version

### 举例

    $ boa brook server -l :9999 -p password

	# 或

    $ boa joker brook server -l :9999 -p password

### 为什么

因为systemd非常复杂

## 开源协议

基于 GPLv3 协议开源
