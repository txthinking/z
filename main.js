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

var help = () => {
console.log(`
jinbe: auto start command at boot

        <command>   add a command
        list        show added commands
        remove <id> remove a command

        help        show help
        version     show version
`);
};

if(Deno.args.length == 0 || (Deno.args.length == 1 && ['help', '-h', '--help'].indexOf(Deno.args[0]) != -1)){
    help();
    Deno.exit(0);
}

if(Deno.args.length == 1 && ['version', '-v', '--version'].indexOf(Deno.args[0]) != -1){
    console.log("v20210401");
    Deno.exit(0);
}

if(Deno.args.length == 1 && Deno.args[0] == 'list'){
    var p = Deno.run({cmd: ["crontab", "-l"], stdout: 'piped', stderr: 'null'});
    var s = new TextDecoder("utf-8").decode(await p.output());
    p.close();
    var l = [];
    s.split("\n").forEach((v, i)=>{
        v = v.trim();
        if(v != ''){
            l.push(v);
            console.log(v.replace("@reboot", `${i}\t`));
        }
    });
    Deno.writeFileSync(`${Deno.env.get("HOME")}/.boacache`, (new TextEncoder("utf-8")).encode(JSON.stringify(l)));
    Deno.exit(0);
}

if(Deno.args.length == 2 && Deno.args[0] == 'remove'){
    var i = parseInt(Deno.args[1]);
    if(isNaN(i) || i < 0){
        console.log("ID must be a number");
        Deno.exit(0);
    }
    var l;
    try{
        l = JSON.parse(Deno.readTextFileSync(`${Deno.env.get("HOME")}/.boacache`));
    }catch(e){
        Deno.exit(0);
    }
    if(l.length == 0 || i > l.length-1){
        Deno.exit(0);
    }
    var p = Deno.run({cmd: ["crontab", "-l"], stdout: 'piped', stderr: 'null'});
    var s = new TextDecoder("utf-8").decode(await p.output());
    p.close();
    var l1 = [];
    s.split("\n").forEach(v=>{
        v = v.trim();
        if(v != '' && v != l[i]){
            l1.push(v);
        }
    });
    p = Deno.run({cmd: ["crontab"], stdout: 'piped',stdin: 'piped',});
    await p.stdin.write(new TextEncoder("utf-8").encode(l1.join("\n")+"\n"));
    await p.stdin.close();
    await p.output();
    p.close();
    Deno.exit(0);
}

var c0 = "";
var c1 = "";
var a = "";
Deno.args.forEach((v, i) => {
    if(i == 0){
        c0 = v;
        return;
    }
    if((c0 == 'joker' || c0.endsWith('/joker')) && i == 1){
        c1 = v;
        return;
    }
    a += v.indexOf(' ') != -1 ? `"${v}" ` : `${v} `;
});
a = a.trim();

if(c0.indexOf('/') == -1){
    var p = Deno.run({cmd: ["which", c0], stdout: 'piped',});
    var s = new TextDecoder("utf-8").decode(await p.output());
    p.close();
    if(s == ''){
        console.log(`Can not find commmand ${c0}, please install ${c0} first`);
        Deno.exit(0);
    }
    c0 = s.trim();
}
if(c1 != '' && c1.indexOf('/') == -1){
    var p = Deno.run({cmd: ["which", c1], stdout: 'piped',});
    var s = new TextDecoder("utf-8").decode(await p.output());
    p.close();
    if(s == ''){
        console.log(`Can not find commmand ${c1}, please install ${c1} first`);
        Deno.exit(0);
    }
    c1 = s.trim();
}
var c = c0;
if(c1 != ''){
    c += ` ${c1}`;
}
if(a != ''){
    c += ` ${a}`;
}

var p = Deno.run({cmd: ["crontab", "-l"], stdout: 'piped', stderr: 'null'});
var s = new TextDecoder("utf-8").decode(await p.output());
p.close();
var l = [];
s.split("\n").forEach(v=>{
    v = v.trim();
    if(v != ''){
        l.push(v);
    }
});
l.push(`@reboot ${c}`);
l = Array.from(new Set(l))

p = Deno.run({cmd: ["crontab"], stdout: 'piped',stdin: 'piped',});
await p.stdin.write(new TextEncoder("utf-8").encode(l.join("\n")+"\n"));
await p.stdin.close();
await p.output();
p.close();
