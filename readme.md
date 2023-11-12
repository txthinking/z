# Zhen

Zhen - process and cron manager

> 名称取自 [先轸](https://zh.wikipedia.org/zh-sg/%E5%85%88%E8%BD%B8)

❤️ A project by [txthinking.com](https://www.txthinking.com)

### Install via [nami](https://github.com/txthinking/nami)

```
nami install joker zhen
```

### Usage

Run zhen background after reboot, sudo or root required. Optional, but usually you need

```
zhen init
```

Run zhen background now, sudo or root required

```
joker zhen background
```

Add a command

```
zhen brook server -l :9999 -p hello
```

Usage

```
zhen: process and cron manager

    init                  run joker zhen background after reboot, sudo or root required
    background            this subcommand must be executed first, recommand: joker zhen background,
                          sudo or root required, it will wait for the network to be ready
    <command>             run command now and run it after reboot
    '* * * * *' <command> add command to cron task
    all                   show all commands
    ps                    show running commands
    st <id>               stop command by SIGTERM
    rs <id>               restart or start command
    rm <id>               remove command
    log <id>              show log of command
    env <key> <value>     set env
    env                   show all envs
```

### Env

As you know, usually when the system just boots up, some environment variables do not exist, such as HOME, and the PATH variable is also relatively concise, and your command may depend on these environment variables, then you can use zhen to set.

For example, set HOME
```
zhen env HOME /root
```
For example, set PATH to current PATH
```
zhen env PATH $PATH
```
Show all env
```
zhen env
```

### Network

As you know, usually when the system just boots up, the network may not be ready yet, don't worry, zhen will run all your commands after the network is ready.

### Why

There are many tools, such as systemd, supervisord, etc.
But I need a simple, small, clean, no configuration tool.

### Where are the old jinbe?

It is in [master](https://github.com/txthinking/zhen/tree/master) branch.
