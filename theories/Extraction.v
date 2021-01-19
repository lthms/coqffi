(** ** Primitive Signed Integers *)

From CoqFFI Require Export Int.
Import IntExtraction.

(** ** Strings *)

From Coq Require Export Ascii String.
From Coq Require Import ExtrOcamlNativeString.

(** ** Booleans *)

Extract Inductive bool => "bool" [ "true" "false" ].
Extract Inlined Constant orb => "(||)".
Extract Inlined Constant andb => "(&&)".

(** ** Options *)

Extract Inductive option => "option" [ "Some" "None" ].

(** ** Unit *)

Extract Inductive unit => unit [ "()" ].

(** ** Products *)

Extract Inductive prod => "( * )" [ "" ].

(** ** Lists *)

Extract Inductive list => "list" [ "[]" "( :: )" ].

(** ** Seq *)

From CoqFFI Require Seq.
Import Seq.SeqExtraction.

(** Exceptions *)

From CoqFFI Require Export Exn.
Import ExnExtraction.
