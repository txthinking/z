# Boa

[中文](readme_zh.md)

Boa can add auto start command at boot

### Install via [nami](https://github.com/txthinking/nami)

```
$ nami install github.com/brook-community/boa
```

### Usage

	boa: auto start command at boot

        <command>   add a command
        list        show added commands
        remove <id> remove a command

        help        show help
        version     show version

### Example

    $ boa brook server -l :9999 -p password

	# OR

    $ boa joker brook server -l :9999 -p password

### Why

Because systemd is very complicated

## License

Licensed under The GPLv3 License
