# jx

## Building, installing

Requires zig (developed with version 0.8.0-\*). This installs `jx` as a binary
under `/usr/local/bin`:

    zig build -Drelease-fast=true --prefix /usr/local

You can also just `zig build` and run the debug build `./zig-cache/bin/jx`.

## Synopsis

Assuming a JSON file:

    $ cat test.json
    {
        "color": "blue",
        "people": [
            { "name": "Alice", "age": 40 },
            { "name": "Bob", "age": 41 },
            { "name": "Cathy", "age": 42}
        ],
        "places": ["here", "there", "everywhere"]
    }

Pipe JSON through `jx` to provide a grep'able interface to the data:

    $ jx < test.json
    color  "blue"
    people.0.name  "Alice"
    people.0.age  40
    people.1.name  "Bob"
    people.1.age  41
    people.2.name  "Cathy"
    people.2.age  42
    places.0  "here"
    places.1  "there"
    places.2  "everywhere"
    $ jx < test.json | grep name
    people.0.name  "Alice"
    people.1.name  "Bob"
    people.2.name  "Cathy"
    $

This doesn't require the stream to complete before providing output, so it's
suitable for viewing data as it's being downloaded (using `tail -F <filename>`
to continually monitor a file):

    $ tail -F /tmp/test.json | jx | grep age
    ... open another terminal ...

    $ curl -s http://localhost:8080/test.json > /tmp/test.json
    ... ages show up in prior terminal ...

More examples:

    $ jx < test.json | awk '/age/ {print $1, $2+7}' # or whatever
    people.0.age 47
    people.1.age 48
    people.2.age 49

    $ jx < test.json | grep '^places'
    places.0  "here"
    places.1  "there"
    places.2  "everywhere"

    $ curl -s https://api.github.com/users/cescude/repos | jx | grep git_url
    0.git_url  "git://github.com/cescude/advent-of-weirdness-2020.git"
    1.git_url  "git://github.com/cescude/aws-lambda-github-merge.git"
    2.git_url  "git://github.com/cescude/csv.git"
    3.git_url  "git://github.com/cescude/dotfiles.git"
    4.git_url  "git://github.com/cescude/golang-collections.git"
    5.git_url  "git://github.com/cescude/heroku-buildpack-scala.git"
    6.git_url  "git://github.com/cescude/hl.git"
    7.git_url  "git://github.com/cescude/hl-native.git"
    8.git_url  "git://github.com/cescude/jr.git"
    9.git_url  "git://github.com/cescude/js-sequence-diagrams.git"
    10.git_url  "git://github.com/cescude/jx.git"
    11.git_url  "git://github.com/cescude/jxji.git"
    12.git_url  "git://github.com/cescude/learning-akka.git"
    13.git_url  "git://github.com/cescude/LocalPlex.git"
    14.git_url  "git://github.com/cescude/mandala.git"
    15.git_url  "git://github.com/cescude/ocaml-collections.git"
    16.git_url  "git://github.com/cescude/presentations.git"
    17.git_url  "git://github.com/cescude/scala-js-dom.git"
    18.git_url  "git://github.com/cescude/scalajs-react.git"
    19.git_url  "git://github.com/cescude/stats.git"
    20.git_url  "git://github.com/cescude/TIC-80.git"
    21.git_url  "git://github.com/cescude/tickets.git"
    22.git_url  "git://github.com/cescude/zig.git"
