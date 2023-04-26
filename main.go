// Copyright (c) 2019-present Cloud <cloud@txthinking.com>
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of version 3 of the GNU General Public
// License as published by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
// General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

var help = `
jinbe: auto start command at boot
        <command>   add a command
        list        show added commands
        remove <id> remove a command
        help        show help
        version     show version
`

func main() {
	if len(os.Args) == 1 || (len(os.Args) == 2 && (os.Args[1] == "help" || os.Args[1] == "-h" || os.Args[1] == "--help")) {
		fmt.Println(help)
		return
	}
	if len(os.Args) == 2 && (os.Args[1] == "version" || os.Args[1] == "-v" || os.Args[1] == "--version") {
		fmt.Println("v20230426")
		return
	}
	if len(os.Args) == 2 && os.Args[1] == "list.hancock" {
		b, _ := exec.Command("crontab", "-l").Output()
		l := strings.Split(string(b), "\n")
		for i, v := range l {
			v = strings.TrimSpace(v)
			if v != "" {
				fmt.Println(strings.Replace(v, "@reboot", strconv.Itoa(i)+"\t", 1))
			}
		}
		return
	}
	if len(os.Args) == 2 && os.Args[1] == "list" {
		b, _ := exec.Command("crontab", "-l").Output()
		l := strings.Split(string(b), "\n")
		l1 := []string{}
		for i, v := range l {
			v = strings.TrimSpace(v)
			if v != "" {
				l1 = append(l1, v)
				fmt.Println(strings.Replace(v, "@reboot", strconv.Itoa(i)+"\t", 1))
			}
		}
		s, err := os.UserHomeDir()
		if err != nil {
			log.Println(err)
			os.Exit(1)
			return
		}
		b, err = json.Marshal(l1)
		if err != nil {
			log.Println(err)
			os.Exit(1)
			return
		}
		err = os.WriteFile(filepath.Join(s, ".jinbe"), b, 0644)
		if err != nil {
			log.Println(err)
			os.Exit(1)
			return
		}
		return
	}
	if len(os.Args) == 3 && os.Args[1] == "remove" {
		id, err := strconv.ParseInt(os.Args[2], 10, 64)
		if err != nil || id < 0 {
			log.Println("ID must be a index number")
			os.Exit(1)
			return
		}
		i := int(id)
		s, err := os.UserHomeDir()
		if err != nil {
			log.Println(err)
			os.Exit(1)
			return
		}
		b, err := os.ReadFile(filepath.Join(s, ".jinbe"))
		if err != nil {
			log.Println(err)
			os.Exit(1)
			return
		}
		l := []string{}
		err = json.Unmarshal(b, &l)
		if err != nil {
			log.Println(err)
			os.Exit(1)
			return
		}
		if len(l) == 0 || i > len(l)-1 {
			return
		}
		b, _ = exec.Command("crontab", "-l").Output()
		l2 := strings.Split(string(b), "\n")
		l3 := []string{}
		for _, v := range l2 {
			v = strings.TrimSpace(v)
			if v != "" && v != l[i] {
				l3 = append(l3, v)
			}
		}
		cmd := exec.Command("crontab")
		stdin, err := cmd.StdinPipe()
		if err != nil {
			log.Println(err)
			os.Exit(1)
			return
		}
		go func() {
			defer stdin.Close()
			_, err := io.WriteString(stdin, strings.Join(l3, "\n")+"\n")
			if err != nil {
				log.Println(err)
			}
		}()
		err = cmd.Run()
		if err != nil {
			log.Println(err)
			os.Exit(1)
			return
		}
		time.Sleep(100 * time.Millisecond)
		return
	}

	c0 := ""
	c1 := ""
	a := ""
	for i, v := range os.Args {
		if i == 0 {
			continue
		}
		if i == 1 {
			c0 = v
			continue
		}
		if (c0 == "joker" || strings.HasSuffix(c0, "/joker")) && i == 2 {
			c1 = v
			continue
		}
		if strings.Contains(v, " ") {
			a += fmt.Sprintf(`"%s" `, v)
		}
		if !strings.Contains(v, " ") {
			a += fmt.Sprintf(`%s `, v)
		}
	}
	a = strings.TrimSpace(a)

	if !strings.Contains(c0, "/") {
		b, _ := exec.Command("which", c0).Output()
		s := string(b)
		if s == "" {
			log.Printf("Can not find commmand %s, please install %s first\n", c0, c0)
			os.Exit(1)
			return
		}
		c0 = strings.TrimSpace(s)
	}
	if c1 != "" && !strings.Contains(c1, "/") {
		b, _ := exec.Command("which", c1).Output()
		s := string(b)
		if s == "" {
			log.Printf("Can not find commmand %s, please install %s first\n", c1, c1)
			os.Exit(1)
			return
		}
		c1 = strings.TrimSpace(s)
	}
	c := c0
	if c1 != "" {
		c += " " + c1
	}
	if a != "" {
		c += " " + a
	}

	b, _ := exec.Command("crontab", "-l").Output()
	l := strings.Split(string(b), "\n")
	l1 := []string{}
	for _, v := range l {
		v = strings.TrimSpace(v)
		if v != "" {
			l1 = append(l1, v)
		}
	}
	l1 = append(l1, "@reboot "+c)
	// stupid two for? yes, it is, but readability in context
	l = []string{}
	for _, v := range l1 {
		got := false
		for _, vv := range l {
			if vv == v {
				got = true
				break
			}
		}
		if !got {
			l = append(l, v)
		}
	}
	cmd := exec.Command("crontab")
	stdin, err := cmd.StdinPipe()
	if err != nil {
		log.Println(err)
		os.Exit(1)
		return
	}
	go func() {
		defer stdin.Close()
		_, err := io.WriteString(stdin, strings.Join(l, "\n")+"\n")
		if err != nil {
			log.Println(err)
		}
	}()
	out, err := cmd.CombinedOutput()
	if err != nil {
		log.Println(string(out))
		os.Exit(1)
		return
	}
	time.Sleep(100 * time.Millisecond)
}
