(** Context free rewriting *)

open Parsetree

(** Local rewriting rules.

    This module lets you define local rewriting rules, such as extension point
    expanders. It is not completely generic and you cannot define any kind of rewriting,
    it currently focuses on what is commonly used. New scheme can be added on demand.

    We have some ideas to make this fully generic, but this hasn't been a priority so
    far.
*)
module Rule : sig type t

  (** Rewrite an extension point *)
  val extension : Extension.t -> t

  (** [special_function id expand] is a rule to rewrite a function call at parsing time.
      [id] is the identifier to match on and [expand] is used to expand the full function
      application (it gets the Pexp_apply node). If the function is found in the tree
      without being applied, [expand] gets only the identifier (Pexp_ident node) so you
      should handle both cases.

      [expand] must decide whether the expression it receive can be rewritten or not.
      Especially ppx_core makes the assumption that [expand] is idempotent. It will loop
      if it is not. *)
  val special_function
    :  string
    -> (Parsetree.expression -> Parsetree.expression option)
    -> t

  (** The rest of this API is for rewriting rules that apply when a certain attribute is
      present. The API is not complete and is currently only enough to implement
      type_conv. *)

  (** Match the attribute on a group of items, such as a group of recursive type
      definitions (Pstr_type, Psig_type). The expander will be triggered if any of the
      item has the attribute. The expander is called as follow:

      [expand ~loc ~path rec_flag items values]

      where [values] is the list of values associated to the attribute for each item in
      [items]. [expand] must return a list of element to add after the group. For instance
      a list of structure item to add after a group of type definitions.
  *)
  type ('a, 'b, 'c) attr_group_inline =
    ('b, 'c) Attribute.t
    -> (loc:Location.t
        -> path:string
        -> Asttypes.rec_flag
        -> 'b list
        -> 'c option list
        -> 'a list)
    -> t

  val attr_str_type_decl : (structure_item, type_declaration, _) attr_group_inline
  val attr_sig_type_decl : (signature_item, type_declaration, _) attr_group_inline

  (** Same as [attr_group_inline] but for elements that are not part of a group, such as
      exceptions and type extensions *)
  type ('a, 'b, 'c) attr_inline =
    ('b, 'c) Attribute.t
    -> (loc:Location.t
        -> path:string
        -> 'b
        -> 'c
        -> 'a list)
    -> t

  val attr_str_type_ext : (structure_item, type_extension, _) attr_inline
  val attr_sig_type_ext : (signature_item, type_extension, _) attr_inline

  val attr_str_exception : (structure_item, extension_constructor, _) attr_inline
  val attr_sig_exception : (signature_item, extension_constructor, _) attr_inline
end

class map_top_down : Rule.t list -> Ast_traverse.map_with_path
