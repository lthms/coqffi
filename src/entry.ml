open Repr
open Parsetree
open Types
open Cmi_format
open Format

type primitive_entry = {
  prim_name : string;
  prim_type : type_repr;
}

type function_entry = {
  func_name : string;
  func_type : type_repr;
  func_model : string option
}

type type_entry = {
  type_name : string;
  type_params : string list;
  type_model : string option;
}

type entry =
  | EPrim of primitive_entry
  | EFunc of function_entry
  | EType of type_entry

exception UnsupportedOCamlSignature of Types.signature_item

let entry_of_signature (s : Types.signature_item) : entry =
  let is_impure attr =
    attr.attr_name.txt = "impure" in

  let has_impure : attributes -> bool =
    List.exists is_impure in

  let expr_to_string = function
    | Pexp_constant (Pconst_string (str, _)) -> Some str
    | _ -> None in

  let struct_to_string = function
    | Pstr_eval (expr, _) -> expr_to_string expr.pexp_desc
    | _ -> None in

  let get_model attr =
    if attr.attr_name.txt = "coq_model"
    then match attr.attr_payload with
      | PStr [ model ] -> struct_to_string model.pstr_desc
      | _ -> None
    else None in

  let find_coq_model = List.find_map get_model in

  match s with
  | Sig_value (ident, desc, Exported) ->
    let name = Ident.name ident in
    let repr = type_repr_of_type_expr desc.val_type in

    if has_impure desc.val_attributes
    then EPrim {
        prim_name = name;
        prim_type = repr;
      }
    else EFunc {
        func_name = name;
        func_type = repr;
        func_model = find_coq_model desc.val_attributes;
      }
  | Sig_type (ident, desc, _, Exported) ->
    let get_poly t =
      match t.desc with
      | Tvar (Some x) -> Some x
      | _ -> None in

    let minimize f l = List.sort_uniq String.compare (List.filter_map f l) in

    let polys = minimize get_poly desc.type_params in

    let name = Ident.name ident in

    EType {
      type_params = polys;
      type_name = name;
      type_model = find_coq_model desc.type_attributes;
    }
  | _ -> raise (UnsupportedOCamlSignature s)

type input_module = {
  module_namespace : string list;
  module_name : string;
  module_types : type_entry list;
  module_functions : function_entry list;
  module_primitives : primitive_entry list;
}

let empty_module (modname : string) =
  let rec namespace_and_path acc = function
    | [x] -> (List.rev acc, x)
    | x :: rst -> namespace_and_path (x :: acc) rst
    | _ -> assert false in

  let (namespace, name) = namespace_and_path [] (Str.split (Str.regexp "__") modname)
  in {
    module_namespace = namespace;
    module_name = name;
    module_types = [];
    module_functions = [];
    module_primitives = [];
  }

let input_module_of_cmi_infos (info : cmi_infos) =
  let add_primitive_entry (m : input_module) (pr : primitive_entry) : input_module = {
    m with
    module_primitives = m.module_primitives @ [pr]
  } in

  let add_function_entry (m : input_module) (f : function_entry) : input_module = {
    m with
    module_functions = m.module_functions @ [f]
  } in

  let add_type_entry (m : input_module) (t : type_entry) : input_module = {
    m with
    module_types = m.module_types @ [t]
  } in

  let add_entry (m : input_module) = function
    | EPrim pr -> add_primitive_entry m pr
    | EFunc fn -> add_function_entry m fn
    | EType t -> add_type_entry m t in

  List.fold_left (fun m s -> entry_of_signature s |> add_entry m)
    (empty_module info.cmi_name)
    info.cmi_sign

let translate tbl m =
  let translate_function tbl f = {
    f with
    func_type = translate_type_repr tbl f.func_type
  } in

  let translate_primitive tbl prim = {
    prim with
    prim_type = translate_type_repr tbl prim.prim_type
  } in

  let tbl' = List.fold_left
      (fun tbl t -> Translation.add t.type_name t.type_name tbl)
      tbl
      m.module_types in

  {
    m with
    module_functions = List.map (translate_function tbl') m.module_functions;
    module_primitives = List.map (translate_primitive tbl') m.module_primitives;
  }

let pp_interface_decl (fmt : formatter) (m : input_module) =
  let interface_name = String.uppercase_ascii m.module_name in
  let prims = m.module_primitives in

  let pp_print_primitive fmt prim =
    fprintf fmt "@[<hov 2>| %s@ : %a@]"
      (String.capitalize_ascii prim.prim_name)
      pp_type_repr_arrows (interface_proj interface_name prim.prim_type) in

  fprintf fmt "@[<v>Inductive %s : interface :=@ %a.@]"
    interface_name
    (pp_print_list ~pp_sep:pp_print_space pp_print_primitive) prims

let pp_interface_freespec_semantics_decl (fmt : formatter) (m : input_module) =
  let interface_name = String.uppercase_ascii m.module_name in
  let semantics_name = String.lowercase_ascii m.module_name in
  let prims = m.module_primitives in

  fprintf fmt "@[<v 2>Definition %s : semantics %s :=@ "
    semantics_name interface_name;
  fprintf fmt
    "@[<v 2>bootstrap (fun a e =>@ local @[<v>match e in %s a return a with@ %a@ end@]).@]@]"
    interface_name
    (pp_print_list ~pp_sep:pp_print_space
    (fun fmt prim ->
       fprintf fmt "| %s %a => ocaml_%s %a"
         (String.capitalize_ascii prim.prim_name)
         pp_type_repr_arg_list prim.prim_type
         prim.prim_name
         pp_type_repr_arg_list prim.prim_type)) prims

let pp_interface_freespec_handlers_decl (fmt : formatter) (m : input_module) =
  let prims = m.module_primitives in

  pp_print_list ~pp_sep:pp_print_space
    (fun fmt prim ->
      fprintf fmt "Axiom (ocaml_%s : %a)."
        prim.prim_name
        pp_type_repr_arrows prim.prim_type) fmt prims

let pp_functions_decl (fmt : formatter) (m : input_module) =
  let pp_function_decl (fmt : formatter) (f : function_entry) =
    match f.func_model with
    | Some model -> fprintf fmt "@[<v 2>@[<hov 2>Definition %s@ : %a :=@]@ %s.@]"
                      f.func_name
                      pp_type_repr_arrows f.func_type
                      model
    | _ -> fprintf fmt "Axiom (%s : %a)."
             f.func_name
             pp_type_repr_arrows f.func_type
  in

  pp_print_list ~pp_sep:(fun fmt _ -> fprintf fmt "@ @ ")
    pp_function_decl fmt m.module_functions

let pp_types_decl (fmt : formatter) (m : input_module) =
  let pp_type_param (fmt : formatter) (params : string list) =
    match params with
    | [] -> pp_print_text fmt "Type"
    | _ -> fprintf fmt "@[<hov 2>@[<hv 2>forall %a,@] Type@]"
             (pp_print_list ~pp_sep:pp_print_space
                (fun fmt name -> fprintf fmt "(%s : Type)" name)) params in

  let pp_type_decl (fmt : formatter) (t : type_entry) =
    match t.type_model with
    | Some model -> fprintf fmt "Definition %s : %a := %s."
                      t.type_name
                      pp_type_param t.type_params
                      model
    | _ -> fprintf fmt "Axiom (%s : %a)."
             t.type_name
             pp_type_param t.type_params
  in

  pp_print_list ~pp_sep:(fun fmt _ -> fprintf fmt "@ @ ")
    pp_type_decl fmt m.module_types

let pp_interface_freespec_primitive_helpers_decl (fmt : formatter) (m : input_module) =
  let interface_name = String.uppercase_ascii m.module_name in

  pp_print_list ~pp_sep:(fun fmt _ -> fprintf fmt "@ @ ")
    (fun fmt prim ->
       let prefix = sprintf "Definition %s `{Provide ix %s}"
           prim.prim_name
           interface_name in
       fprintf fmt "@[<hv 2>%a :=@ request (%s %a)@]."
         (pp_type_repr_prototype prefix) (impure_proj "ix" prim.prim_type)
         (String.capitalize_ascii prim.prim_name)
         pp_type_repr_arg_list prim.prim_type)
    fmt m.module_primitives

let pp_interface_handlers_extract_decl (fmt : formatter) (m : input_module) =
  let prims = m.module_primitives in

  pp_print_list ~pp_sep:pp_print_space
    (fun fmt prim ->
       fprintf fmt "@[<hov 2>Extract Constant ocaml_%s@ => \"%s.%s.%s\".@]"
         prim.prim_name
         (String.concat "." m.module_namespace)
         m.module_name
         prim.prim_name) fmt prims

let pp_types_extract_decl (fmt : formatter) (m : input_module) =
  let print_args_list = pp_print_list (fun fmt x -> fprintf fmt " \"'%s\"" x) in

  let print_args_prod fmt = function
    | [] -> ()
    | [x] -> fprintf fmt "'%s " x
    | args -> fprintf fmt "(%a) "
                (pp_print_list ~pp_sep:(fun fmt _ -> pp_print_text fmt ", ")
                   (fun fmt -> fprintf fmt "'%s")) args in

  pp_print_list ~pp_sep:pp_print_space
    (fun fmt t ->
       fprintf fmt "@[<hov 2>Extract Constant %s%a@ => \"%a%s.%s.%s\".@]"
         t.type_name
         print_args_list t.type_params
         print_args_prod t.type_params
         (String.concat "." m.module_namespace)
         m.module_name
         t.type_name) fmt m.module_types

let pp_functions_extract_decl (fmt : formatter) (m : input_module) =
  pp_print_list ~pp_sep:pp_print_space
    (fun fmt f ->
       fprintf fmt "@[<hov 2>Extract Constant %s@ => \"%s.%s.%s\".@]"
         f.func_name
         (String.concat "." m.module_namespace)
         m.module_name
         f.func_name) fmt m.module_functions

let pp_impure_decl mode fmt m =
  match mode with
  | Some Cli.FreeSpec -> begin
      fprintf fmt "(** * Impure Primitives *)@ @ ";

      fprintf fmt "(** ** Interface Definition *)@ @ ";

      fprintf fmt "@[<v>%a@]@ @ "
        pp_interface_decl m;

      fprintf fmt "(** ** Primitive Helpers *)@ @ ";

      fprintf fmt "@[<v>%a@]@ @ "
        pp_interface_freespec_primitive_helpers_decl m
    end
  | _ -> ()

let pp_impure_extraction mode fmt m =
  match mode with
  | Some Cli.FreeSpec -> begin
      fprintf fmt "@[<v>%a@]@ @ "
        pp_interface_freespec_handlers_decl m;

      fprintf fmt "@[<v>%a@]@ @ "
        pp_interface_handlers_extract_decl m;

      fprintf fmt "@[<v>%a@]"
        pp_interface_freespec_semantics_decl m
    end
  | _ -> ()

let pp_extraction_profile_import fmt = function
  | Cli.Stdlib -> ()
  | Cli.Coqbase -> fprintf fmt "From Base Require Import Prelude.@ "

let pp_impure_mode_import fmt = function
  | Some Cli.FreeSpec ->
    fprintf fmt "From FreeSpec.Core Require Import All.@ "
  | _ -> ()

let pp_input_module (profile : Cli.extraction_profile) (mode : Cli.impure_mode option)
    (fmt : formatter) (m : input_module) =
  pp_open_vbox fmt 0;
  fprintf fmt "(* This file has been generated by coqffi. *)@ @ ";

  fprintf fmt "Set Implicit Arguments.@ @ ";

  pp_extraction_profile_import fmt profile;
  pp_impure_mode_import fmt mode;

  fprintf fmt "@ (** * Types *)@ @ ";

  fprintf fmt "@[<v>%a@]@ @ "
    pp_types_decl m;

  fprintf fmt "(** * Pure Functions *)@ @ ";

  fprintf fmt "@[<v>%a@]@ @ "
    pp_functions_decl m;

  pp_impure_decl mode fmt m;

  fprintf fmt "(** * Extraction *)@ @ ";

  fprintf fmt "@[<v 2>Module %sExtr.@ "
    m.module_name;

  fprintf fmt "@[<v>%a@]@ "
    pp_types_extract_decl m;
  fprintf fmt "@[<v>%a@]@ "
    pp_functions_extract_decl m;

  pp_impure_extraction mode fmt m;

  fprintf fmt "@]@ End %sExtr.@?"
    m.module_name;
  pp_close_box fmt ()