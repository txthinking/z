# Jinbe

[中文](readme_zh.md)

Jinbe can add auto start command at boot

### Install via [nami](https://github.com/txthinking/nami)

```
$ nami install github.com/txthinking/jinbe
```

### Usage

	jinbe: auto start command at boot

        <command>   add a command
        list        show added commands
        remove <id> remove a command

        help        show help
        version     show version

### Example

    $ jinbe brook server -l :9999 -p password

	# OR

    $ jinbe joker brook server -l :9999 -p password

### Why

Because systemd is very complicated

## Author

A project by [txthinking](https://www.txthinking.com)

## License

Licensed under The GPLv3 License
