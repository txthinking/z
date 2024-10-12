# Z

z - process manager

❤️ A project by [txthinking.com](https://www.txthinking.com)

### Install via [nami](https://github.com/txthinking/nami)

```
nami install z
```

### Usage

1. start z daemon and add z into system boot. [this step requires root privileges] and [z requires your system to support the IPv6 stack]

    ```
    z start
    ```
1. [Optional] Because z will start all the commands it manages at system boot, and your command could depend on certain environment variables, yet there are hardly any environment variables present right after the system starts. Thus, you will need to add the necessary environment variables according to the requirements of your command, for example:
    ```
    z e PATH $PATH
    z e HOME /root
    ```
1. Add a command

    ```
    z brook server -l :9999 -p hello
    ```

Usage

```
z - process manager

    start                             start z daemon and add z into system boot [root and ipv6 stack required]

    <command> <arg1> <arg2> <...>     add and run command
    a                                 print all commands
    s <id>                            stop a command
    r <id>                            restart a command
    d <id>                            delete a command

    e <k> <v>                         add environment variable
    e                                 print all environment variables

    <id>                              print stdout and stderr of command
    z                                 print stdout and stderr of z

    stop                              stop z daemon
```

### Network

As you know, usually when the system just boots up, the network may not be ready yet, don't worry, zhen will run all your commands after the network is ready.

### Why

Because [systemd](https://nosystemd.org/) has made the world more complicated.

