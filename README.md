# `coqffi`

**`coqffi` automatically generates Coq FFI bindings to OCaml
libraries.**

For example, given the OCaml header file `file.mli`:

```ocaml
open Coqbase

type fd

val fd_equal : fd -> fd -> bool

val openfile : Bytestring.t -> fd [@@impure]
val read_all : fd -> Bytestring.t [@@impure]
val write : fd -> Bytestring.t -> unit [@@impure]
val closefile : fd -> unit [@@impure]
```

`coqffi` generates the necessary Coq boilerplate to use these
functions in a Coq development, and to configure the extraction
mechanism accordingly.

```coq
(* This file has been generated by coqffi. *)

Set Implicit Arguments.
Generalizable All Variables.

From Base Require Import Prelude Extraction.
From FreeSpec.Core Require Import All.

(** * Types *)

Axiom (fd : Type).

Extract Constant fd => "Examples.File.fd".

(** * Pure Functions *)

Axiom (fd_equal : fd -> fd -> bool).

Extract Constant fd_equal => "Examples.File.fd_equal".

(** * Impure Primitives *)

(** ** Interface Definition *)

Inductive FILE : interface :=
| Openfile : bytestring -> FILE fd
| Read_all : fd -> FILE bytestring
| Write : fd -> bytestring -> FILE unit
| Closefile : fd -> FILE unit.

(** ** Primitive Helpers *)

Definition openfile `{Provide ix FILE} (x0 : bytestring) : impure ix fd :=
  request (Openfile x0).

Definition read_all `{Provide ix FILE} (x0 : fd) : impure ix bytestring :=
  request (Read_all x0).

Definition write `{Provide ix FILE} (x0 : fd) (x1 : bytestring)
  : impure ix unit :=
  request (Write x0 x1).

Definition closefile `{Provide ix FILE} (x0 : fd) : impure ix unit :=
  request (Closefile x0).

Axiom (ml_openfile : bytestring -> fd).
Axiom (ml_read_all : fd -> bytestring).
Axiom (ml_write : fd -> bytestring -> unit).
Axiom (ml_closefile : fd -> unit).

Extract Constant ml_openfile => "Examples.File.openfile".
Extract Constant ml_read_all => "Examples.File.read_all".
Extract Constant ml_write => "Examples.File.write".
Extract Constant ml_closefile => "Examples.File.closefile".

Definition ml_file_sem : semantics FILE :=
  bootstrap (fun a e =>
    local match e in FILE a return a with
          | Openfile x0 => ml_openfile x0
          | Read_all x0 => ml_read_all x0
          | Write x0 x1 => ml_write x0 x1
          | Closefile x0 => ml_closefile x0
          end).
```

`coqffi` can be configured through two key options:

- The “extraction profile” determines the set of supported
  “base”. Currently, `coqffi` provides two profiles: `stdlib` and
  `coq-base`.
- The “impure mode” determines which framework is used to model impure
  functions. Currently, `coqffi` provides one mode:
  [`FreeSpec`](https://github.com/ANSSI-FR/FreeSpec). We expect to
  support more frameworks in the future, such as [Interaction
  Trees](https://github.com/DeepSpec/InteractionTrees)

Besides, it provides several flags to enable certain experimental
features:

- `-ftransparent-types` to generate Coq definitions for types whose
  implementation is public. **Note:** `coqffi` does only support a
  subset of OCaml’s types, and may generate invalid Coq types.

# Getting Started

## Building From Source

To build

- [scdoc](https://sr.ht/~sircmpwn/scdoc/) (generating the `coqffi` man page)

```
dune build -p coqffi
dune install
```

## Building the Examples

If you want to build the examples using `dune build`, you will need to
install the following dependencies:

- [FreSspec](https://github.com/ANSSI-FR/FreeSpec) (compiling the examples)
