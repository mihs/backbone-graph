backbone-graph
==============

Lightweight library for [Backbone](https://github.com/jashkenas/backbone) model relations.

# Overview

Enables One-to-One, One-to-Many and Many-to-Many relations for Backbone models.

## Written with the following goals in mind

* Lightweight but support the basic relation types. If something more complicated is needed then it should be written in the application layer.
* Models are instantiated only once.
* A data store that contains all the Backbone models.
* Ability to update/add an entire subgraph of models by setting the attributes directly on the data store (e.g. when an update comes through a real time update mechanism such as socket.io, just apply it to the datastore).

# Usage

See tests until docs are written.

# Test

`make test`

# TODO

* More tests
* Docs
* Refactor the code

# Related libraries

* [Backbone-relational](https://github.com/PaulUithol/Backbone-relational)
* TBW
