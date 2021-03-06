open StdLabels
open MoreLabels
open Common

module String_map = Map.Make(String)

type (_, _) equality = Eq : ('a, 'a) equality | Ne : (_, _) equality

module Context = struct
  open Parsetree

  type 'a t =
    | Class_expr       : class_expr       t
    | Class_field      : class_field      t
    | Class_type       : class_type       t
    | Class_type_field : class_type_field t
    | Core_type        : core_type        t
    | Expression       : expression       t
    | Module_expr      : module_expr      t
    | Module_type      : module_type      t
    | Pattern          : pattern          t
    | Signature_item   : signature_item   t
    | Structure_item   : structure_item   t

  type packed = T : _ t -> packed

  let class_expr       = Class_expr
  let class_field      = Class_field
  let class_type       = Class_type
  let class_type_field = Class_type_field
  let core_type        = Core_type
  let expression       = Expression
  let module_expr      = Module_expr
  let module_type      = Module_type
  let pattern          = Pattern
  let signature_item   = Signature_item
  let structure_item   = Structure_item

  let desc : type a. a t -> string = function
    | Class_expr       -> "class expression"
    | Class_field      -> "class field"
    | Class_type       -> "class type"
    | Class_type_field -> "class type field"
    | Core_type        -> "core type"
    | Expression       -> "expression"
    | Module_expr      -> "module expression"
    | Module_type      -> "module type"
    | Pattern          -> "pattern"
    | Signature_item   -> "signature item"
    | Structure_item   -> "structure item"

  let eq : type a b. a t -> b t -> (a, b) equality = fun a b ->
    match a, b with
    | Class_expr       , Class_expr       -> Eq
    | Class_field      , Class_field      -> Eq
    | Class_type       , Class_type       -> Eq
    | Class_type_field , Class_type_field -> Eq
    | Core_type        , Core_type        -> Eq
    | Expression       , Expression       -> Eq
    | Module_expr      , Module_expr      -> Eq
    | Module_type      , Module_type      -> Eq
    | Pattern          , Pattern          -> Eq
    | Signature_item   , Signature_item   -> Eq
    | Structure_item   , Structure_item   -> Eq
    | _ -> assert (T a <> T b); Ne

  let get_extension : type a. a t -> a -> (extension * attributes) option = fun t x ->
    match t, x with
    | Class_expr       , {pcl_desc =Pcl_extension  e; pcl_attributes =a;_} -> Some (e, a)
    | Class_field      , {pcf_desc =Pcf_extension  e; pcf_attributes =a;_} -> Some (e, a)
    | Class_type       , {pcty_desc=Pcty_extension e; pcty_attributes=a;_} -> Some (e, a)
    | Class_type_field , {pctf_desc=Pctf_extension e; pctf_attributes=a;_} -> Some (e, a)
    | Core_type        , {ptyp_desc=Ptyp_extension e; ptyp_attributes=a;_} -> Some (e, a)
    | Expression       , {pexp_desc=Pexp_extension e; pexp_attributes=a;_} -> Some (e, a)
    | Module_expr      , {pmod_desc=Pmod_extension e; pmod_attributes=a;_} -> Some (e, a)
    | Module_type      , {pmty_desc=Pmty_extension e; pmty_attributes=a;_} -> Some (e, a)
    | Pattern          , {ppat_desc=Ppat_extension e; ppat_attributes=a;_} -> Some (e, a)
    | Signature_item   , {psig_desc=Psig_extension(e, a)               ;_} -> Some (e, a)
    | Structure_item   , {pstr_desc=Pstr_extension(e, a)               ;_} -> Some (e, a)
    | _ -> None

  let merge_attributes : type a. a t -> a -> attributes -> a = fun t x attrs ->
    match t with
    | Class_expr       -> { x with pcl_attributes  = x.pcl_attributes  @ attrs }
    | Class_field      -> { x with pcf_attributes  = x.pcf_attributes  @ attrs }
    | Class_type       -> { x with pcty_attributes = x.pcty_attributes @ attrs }
    | Class_type_field -> { x with pctf_attributes = x.pctf_attributes @ attrs }
    | Core_type        -> { x with ptyp_attributes = x.ptyp_attributes @ attrs }
    | Expression       -> { x with pexp_attributes = x.pexp_attributes @ attrs }
    | Module_expr      -> { x with pmod_attributes = x.pmod_attributes @ attrs }
    | Module_type      -> { x with pmty_attributes = x.pmty_attributes @ attrs }
    | Pattern          -> { x with ppat_attributes = x.ppat_attributes @ attrs }
    | Signature_item   -> assert_no_attributes attrs; x
    | Structure_item   -> assert_no_attributes attrs; x
end

let registrar =
  Name.Registrar.create
    ~kind:"extension"
    ~current_file:__FILE__
    ~string_of_context:(fun (Context.T ctx) -> Some (Context.desc ctx))
;;

module Make(Callback : sig type 'a t end) = struct

  type ('a, 'b) payload_parser =
      Payload_parser : ('a, 'b, 'c) Ast_pattern.t * 'b Callback.t
      -> ('a, 'c) payload_parser

  type ('context, 'payload) t =
    { name     : string
    ; context  : 'context Context.t
    ; payload  : (Parsetree.payload, 'payload) payload_parser
    }

  let declare name context pattern k =
    Name.Registrar.register ~kind:`Extension registrar (Context.T context) name;
    { name
    ; context
    ; payload = Payload_parser (pattern, k)
    }
  ;;

  let find ts (ext : Parsetree.extension) =
    let name = fst ext in
    match List.filter ts ~f:(fun t -> Name.matches ~pattern:t.name name.txt) with
    | [] -> None
    | [t] -> Some t
    | l ->
      Location.raise_errorf ~loc:name.loc
        "Multiple match for extensions: %s"
        (String.concat ~sep:", " (List.map l ~f:(fun t -> t.name)))
  ;;
end

module Expert = struct
  include Make(struct type 'a t = 'a end)

  let convert ts ~loc ext =
    match find ts ext with
    | None -> None
    | Some { payload = Payload_parser (pattern, f); _ } ->
      Some (Ast_pattern.parse pattern loc (snd ext) f)
end

module M = Make(struct type 'a t = loc:Location.t -> path:string -> 'a end)

type 'a expander_result =
  | Simple of 'a
  | Inline of 'a list

module For_context = struct
  type 'a t = ('a, 'a expander_result) M.t

  let convert ts ~loc ~path ext =
    match M.find ts ext with
    | None -> None
    | Some { payload = M.Payload_parser (pattern, f); _  } ->
      match Ast_pattern.parse pattern loc (snd ext) (f ~loc ~path) with
      | Simple x -> Some x
      | Inline _ -> failwith "Extension.convert"
  ;;

  let convert_inline ts ~loc ~path ext =
    match M.find ts ext with
    | None -> None
    | Some { payload = M.Payload_parser (pattern, f); _  } ->
      match Ast_pattern.parse pattern loc (snd ext) (f ~loc ~path) with
      | Simple x -> Some [x]
      | Inline l -> Some l
  ;;
end

type t = T : _ For_context.t -> t

let declare name context pattern k =
  let pattern = Ast_pattern.map_result pattern ~f:(fun x -> Simple x) in
  T (M.declare name context pattern k)
;;

let check_context_for_inline : type a. func:string -> a Context.t -> unit =
  fun ~func ctx ->
    match ctx with
    | Context.Class_field      -> ()
    | Context.Class_type_field -> ()
    | Context.Signature_item   -> ()
    | Context.Structure_item   -> ()
    | context ->
      Printf.ksprintf invalid_arg "%s: %s can't be inlined"
        func
        (Context.desc context)
;;

let declare_inline name context pattern k =
  check_context_for_inline context ~func:"Extension.declare_inline";
  let pattern = Ast_pattern.map_result pattern ~f:(fun x -> Inline x) in
  T (M.declare name context pattern k)
;;

let rec filter_by_context
    : type a. a Context.t -> t list -> a For_context.t list =
    fun context expanders ->
      match expanders with
      | [] -> []
      | T t :: rest ->
        match Context.eq context t.context with
        | Eq -> t :: filter_by_context context rest
        | Ne ->      filter_by_context context rest
;;

let fail ctx (name, _) =
  if not (Name.Whitelisted.is_whitelisted name.Location.txt
          || Name.Reserved_namespaces.is_in_reserved_namespaces name.txt) then
  Name.Registrar.raise_errorf registrar (Context.T ctx)
    "Extension `%s' was not translated" name
;;

let check_unused = object
  inherit Ast_traverse.iter as super

  method! extension (name, _) =
    Location.raise_errorf ~loc:name.loc
      "extension not expected here, Ppx_core.Std.Extension needs updating!"

  method! core_type_desc = function
    | Ptyp_extension ext -> fail Core_type ext
    | x -> super#core_type_desc x

  method! pattern_desc = function
    | Ppat_extension ext -> fail Pattern ext
    | x -> super#pattern_desc x

  method! expression_desc = function
    | Pexp_extension ext -> fail Expression ext
    | x -> super#expression_desc x

  method! class_type_desc = function
    | Pcty_extension ext -> fail Class_type ext
    | x -> super#class_type_desc x

  method! class_type_field_desc = function
    | Pctf_extension ext -> fail Class_type_field ext
    | x -> super#class_type_field_desc x

  method! class_expr_desc = function
    | Pcl_extension ext -> fail Class_expr ext
    | x -> super#class_expr_desc x

  method! class_field_desc = function
    | Pcf_extension ext -> fail Class_field ext
    | x -> super#class_field_desc x

  method! module_type_desc = function
    | Pmty_extension ext -> fail Module_type ext
    | x -> super#module_type_desc x

  method! signature_item_desc = function
    | Psig_extension (ext, _) -> fail Signature_item ext
    | x -> super#signature_item_desc x

  method! module_expr_desc = function
    | Pmod_extension ext -> fail Module_expr ext
    | x -> super#module_expr_desc x

  method! structure_item_desc = function
    | Pstr_extension (ext, _) -> fail Structure_item ext
    | x -> super#structure_item_desc x
end

module V2 = struct
  type nonrec t = t
  let declare = declare
  let declare_inline = declare_inline
end
