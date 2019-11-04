# Godsmen Foundry

[![Build Status](https://dev.azure.com/int-index/Personal/_apis/build/status/serokell.foundry?branchName=master)](https://dev.azure.com/int-index/Personal/_build/latest?definitionId=3&branchName=master)
[![Build Status](https://travis-ci.org/serokell/foundry.svg?branch=master)](https://travis-ci.org/serokell/foundry)

Godsmen Foundry is a Morte IDE based on Source.

Implementation status:

* [x] rendering expressions
* [x] basic navigation
* [x] editing expressions
* [ ] interactive evaluation
* [ ] auto-completion
* [ ] local storage
* [ ] browsing Sigil

[sigil.place/tutorial/morte/1.2/even](http://sigil.place/tutorial/morte/1.2/even)
![Rendering Morte](https://pbs.twimg.com/media/CMuX9DxUcAAZSYh.png:large)

## Getting Started

```
$ nix-build
$ result/bin/morte-to-sdam "./expr.morte" > expr.sd
$ result/bin/foundry expr.sd
```
