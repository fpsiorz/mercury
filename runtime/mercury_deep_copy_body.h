/*
** Copyright (C) 1997-1999 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** The internals of deep copy.
**
** Functions such as "copy", "copy_arg", "copy_type_info", "in_range",
** etc can be #defined to whatever functions are needed for a particular
** copying application.
*/

/*
** Prototypes.
*/
static  Word    copy_arg(maybeconst Word *data_ptr, const Word *type_info,
                        const Word *arg_type_info, const Word *lower_limit,
                        const Word *upper_limit);
static  Word    *copy_type_info(maybeconst Word *type_info,
                        const Word *lower_limit, const Word *upper_limit);

Word 
copy(maybeconst Word *data_ptr, const Word *type_info, 
         const Word *lower_limit, const Word *upper_limit)
{
    MR_TypeCtorInfo type_ctor_info;
    MR_TypeCtorLayout type_ctor_layout;
    MR_TypeCtorFunctors type_ctor_functors;

    Word functors_indicator;
    Word layout_entry, *entry_value, *data_value;
    MR_TypeCtorRepresentation type_ctor_rep;
    MR_DiscUnionTagRepresentation tag_rep;
    int data_tag; 
    Word new_data, data;

    data = *data_ptr;

    data_tag = MR_tag(data);
    data_value = (Word *) MR_body(data, data_tag);

    type_ctor_info = MR_TYPEINFO_GET_TYPE_CTOR_INFO(type_info);
    layout_entry = type_ctor_info->type_ctor_layout[data_tag];
    entry_value = (Word *) MR_strip_tag(layout_entry);

    switch (type_ctor_info->type_ctor_rep) {
        case MR_TYPECTOR_REP_ENUM:
            new_data = data;    /* just a copy of the actual item */
            break;

        case MR_TYPECTOR_REP_DU:
            tag_rep = MR_get_tag_representation(layout_entry);
            switch (tag_rep) {

            case MR_DISCUNIONTAG_SHARED_LOCAL:
                new_data = data;        /* just a copy of the actual item */
                break;

            case MR_DISCUNIONTAG_SHARED_REMOTE: {
                Word secondary_tag;
                Word *new_entry;
                Word *argument_vector, *type_info_vector;
                int arity, i;

                /*
                ** if the vector containing the secondary tags and the
                ** arguments is in range, copy it.
                */
                if (in_range(data_value)) {
                    secondary_tag = *data_value;
                    argument_vector = data_value + 1;

                    new_entry = MR_TYPE_CTOR_LAYOUT_SHARED_REMOTE_VECTOR_GET_FUNCTOR_DESCRIPTOR(
                            entry_value, secondary_tag);
                    arity = new_entry[TYPE_CTOR_LAYOUT_UNSHARED_ARITY_OFFSET];
                    type_info_vector = new_entry + 
                            TYPE_CTOR_LAYOUT_UNSHARED_ARGS_OFFSET;

                    /* allocate space for new args, and secondary tag */
                    incr_saved_hp(new_data, arity + 1);

                    /* copy secondary tag */
                    MR_field(0, new_data, 0) = secondary_tag;

                    /* copy arguments */
                    for (i = 0; i < arity; i++) {
                        MR_field(0, new_data, i + 1) = copy_arg(
                            &argument_vector[i], type_info,
                            (Word *) type_info_vector[i], lower_limit,
                            upper_limit);
                    }

                    /* tag this pointer */
                    new_data = (Word) MR_mkword(data_tag, new_data);
                    leave_forwarding_pointer(data_ptr, new_data);
                } else {
                    new_data = data;
                    found_forwarding_pointer(data);
                }
            break;
            }

            case MR_DISCUNIONTAG_UNSHARED: {
                int arity, i;
                Word *argument_vector, *type_info_vector;
                argument_vector = data_value;

                /* If the argument vector is in range, copy the arguments */
                if (in_range(argument_vector)) {
                    arity = entry_value[TYPE_CTOR_LAYOUT_UNSHARED_ARITY_OFFSET];
                    type_info_vector = entry_value + 
                            TYPE_CTOR_LAYOUT_UNSHARED_ARGS_OFFSET;

                    /* allocate space for new args. */
                    incr_saved_hp(new_data, arity);

                    /* copy arguments */
                    for (i = 0; i < arity; i++) {
                        MR_field(0, new_data, i) = copy_arg(
                            &argument_vector[i],
                            type_info, (Word *) type_info_vector[i],
                            lower_limit, upper_limit);
                    }
                    /* tag this pointer */
                    new_data = (Word) MR_mkword(data_tag, new_data);
                    leave_forwarding_pointer(data_ptr, new_data);
                } else {
                    new_data = data;
                    found_forwarding_pointer(data);
                }
                break;
            }
        }
        break;
        case MR_TYPECTOR_REP_NOTAG:
            new_data = copy_arg(data_ptr, type_info, 
                    (Word *) *MR_TYPE_CTOR_LAYOUT_NO_TAG_VECTOR_ARGS(
                     entry_value), lower_limit, upper_limit);
            break;

        case MR_TYPECTOR_REP_EQUIV: 
            new_data = copy_arg(data_ptr, type_info, 
                (const Word *) MR_TYPE_CTOR_LAYOUT_EQUIV_TYPE((Word *)
                        entry_value), lower_limit, upper_limit);
            break;

        case MR_TYPECTOR_REP_EQUIV_VAR:
            new_data = copy(data_ptr, (Word *) type_info[(Word) entry_value],
                    lower_limit, upper_limit);
            break;

        case MR_TYPECTOR_REP_INT:  /* fallthru */
        case MR_TYPECTOR_REP_CHAR:
            new_data = data;
            break;

        case MR_TYPECTOR_REP_FLOAT:
            #ifdef BOXED_FLOAT
                if (in_range(data_value)) {
                    restore_transient_hp();
                    new_data = word_to_float(float_to_word(data));
                    save_transient_hp();
                    leave_forwarding_pointer(data_ptr, new_data);
                } else {
                    new_data = data;
                    found_forwarding_pointer(data);
                }
            #else
                new_data = data;
            #endif
            break;

        case MR_TYPECTOR_REP_STRING:
            if (in_range(data_value)) {
                incr_saved_hp_atomic(new_data, 
                    (strlen((String) data) + sizeof(Word)) / sizeof(Word));
                strcpy((String) new_data, (String) data);
                leave_forwarding_pointer(data_ptr, new_data);
            } else {
                new_data = data;
                found_forwarding_pointer(data);
            }
            break;

        case MR_TYPECTOR_REP_PRED:
            /*
            ** predicate closures store the number of curried arguments
            ** as their first argument, the Code * as their second, and
            ** then the arguments
            **
            ** Their type-infos have a pointer to type_ctor_info for
            ** pred/0, arity, and then argument typeinfos.
            */
            if (in_range(data_value)) {
                Unsigned args, i;
                MR_Closure *old_closure;
                MR_Closure *new_closure;
                MR_Closure_Layout *closure_layout;

                old_closure = (MR_Closure *) data_value;
                closure_layout = old_closure->MR_closure_layout;
                args = old_closure->MR_closure_num_hidden_args;

                /* create new closure */
                incr_saved_hp(LVALUE_CAST(Word, new_closure), args + 3);

                /* copy the fixed fields */
                new_closure->MR_closure_layout = closure_layout;
                new_closure->MR_closure_num_hidden_args = args;
                new_closure->MR_closure_code = old_closure->MR_closure_code;

                /* copy the arguments */
                for (i = 0; i < args; i++) {
                    Word *arg_pseudo_type_info =
                    	(Word *) closure_layout->arg_pseudo_type_info[i];
                    new_closure->MR_closure_hidden_args_0[i] =
                        copy_arg(
                            &old_closure->MR_closure_hidden_args_0[i],
                            type_info + TYPEINFO_OFFSET_FOR_PRED_ARGS - 1,
                            arg_pseudo_type_info,
                            lower_limit, upper_limit
                        );
                }

                new_data = (Word) new_closure;
                leave_forwarding_pointer(data_ptr, new_data);
            } else {
                new_data = data;
                found_forwarding_pointer(data);
            }
            break;

        case MR_TYPECTOR_REP_UNIV: 
            /* if the univ is stored in range, copy it */ 
            if (in_range(data_value)) {
                Word *new_data_ptr;

                /* allocate space for a univ */
                incr_saved_hp(new_data, 2);
                new_data_ptr = (Word *) new_data;
                /*
                ** Copy the fields across.
                ** Note: we must copy the data before the type_info,
                ** because when copying the data, we need the type_info
                ** to still contain the type rather than just holding
                ** a forwarding pointer.
                */
                new_data_ptr[UNIV_OFFSET_FOR_DATA] = copy(
                        &data_value[UNIV_OFFSET_FOR_DATA], 
                        (const Word *) data_value[UNIV_OFFSET_FOR_TYPEINFO],
                        lower_limit, upper_limit);
                new_data_ptr[UNIV_OFFSET_FOR_TYPEINFO] = 
                    (Word) copy_type_info( 
                        &data_value[UNIV_OFFSET_FOR_TYPEINFO],
                        lower_limit, upper_limit);
                leave_forwarding_pointer(data_ptr, new_data);
            } else {
                new_data = data;
                found_forwarding_pointer(data);
            }
            break;

        case MR_TYPECTOR_REP_VOID:
            fatal_error("Cannot copy a void type");
            break;

        case MR_TYPECTOR_REP_ARRAY: {
            int i;

            if (in_range(data_value)) {
                MR_ArrayType *new_array;
                MR_ArrayType *old_array;
                Integer array_size;

                old_array = (MR_ArrayType *) data_value;
                array_size = old_array->size;
                new_array = MR_make_array(array_size);
                new_array->size = array_size;
                for (i = 0; i < array_size; i++) {
                    new_array->elements[i] = copy_arg(
                        &old_array->elements[i], type_info, 
                        (const Word *) 1, lower_limit, upper_limit);
                }
                new_data = (Word) new_array;
                leave_forwarding_pointer(data_ptr, new_data);
            } else {
                new_data = data;
                found_forwarding_pointer(data);
            }
            break;
        }

        case MR_TYPECTOR_REP_TYPEINFO:
            new_data = (Word) copy_type_info(data_ptr,
                lower_limit, upper_limit);
            break;

        case MR_TYPECTOR_REP_C_POINTER:
            if (in_range(data_value)) {
                /*
                ** This error occurs if we try to copy() a
                ** `c_pointer' type that points to memory allocated
                ** on the Mercury heap.
                */
                fatal_error("Cannot copy a c_pointer type");
            } else {
                new_data = data;
            }
            break;

        case MR_TYPECTOR_REP_SUCCIP: /* fallthru */
        case MR_TYPECTOR_REP_REDOIP:
	    /* code addresses are never relocated */
            new_data = data;
            break;

        case MR_TYPECTOR_REP_HP:
            /*
	    ** Tyson hasn't yet moved the code for copying saved heap pointers
	    ** here.
	    */
            fatal_error("Sorry, not implemented: copying saved heap pointers");
            break;

        case MR_TYPECTOR_REP_CURFR: /* fallthru */
        case MR_TYPECTOR_REP_MAXFR:
	    /* we do not modify the layout of the nondet stack */
            new_data = data;
            break;

        case MR_TYPECTOR_REP_TRAIL_PTR:
        case MR_TYPECTOR_REP_TICKET:
	    /* XXX we do not yet compress the trail when doing gc */
            new_data = data;
            break;

        case MR_TYPECTOR_REP_UNKNOWN: /* fallthru */
        default:
            fatal_error("Unknown layout type in deep copy");
            break;
    }

    return new_data;
}

/*
** copy_arg is like copy() except that it takes a
** pseudo_type_info (namely arg_pseudo_type_info) rather than
** a type_info.  The pseudo_type_info may contain type variables,
** which refer to arguments of the term_type_info.
*/
static Word
copy_arg(maybeconst Word *data_ptr, const Word *term_type_info,
                const Word *arg_pseudo_type_info, const Word *lower_limit,
                const Word *upper_limit)
{
        MR_MemoryList allocated_memory_cells;
        Word *new_type_info;
        Word new_data;

        allocated_memory_cells = NULL;
        new_type_info = MR_make_type_info(term_type_info, arg_pseudo_type_info,
                                        &allocated_memory_cells);
        new_data = copy(data_ptr, new_type_info, lower_limit, upper_limit);
        MR_deallocate(allocated_memory_cells);

        return new_data;
}

static Word *
copy_type_info(maybeconst Word *type_info_ptr, const Word *lower_limit,
                const Word *upper_limit)
{
        Word *type_info = (Word *) *type_info_ptr;

        if (in_range(type_info)) {
                MR_TypeCtorInfo type_ctor_info;
                Word *new_type_info;
                Integer arity, offset, i;

                /*
                ** Note that we assume type_ctor_infos will always be
                ** allocated statically, so we never copy them.
                */

                type_ctor_info = MR_TYPEINFO_GET_TYPE_CTOR_INFO((Word *)
                        type_info);
                /*
                ** optimize special case: if there's no arguments,
                ** we don't need to construct a type_info; instead,
                ** we can just return the type_ctor_info.
                */
                if ((Word) type_info == (Word) type_ctor_info) {
                        return (Word *) type_ctor_info;
                }
                if (MR_TYPE_CTOR_INFO_IS_HO(type_ctor_info)) {
                        arity = MR_TYPEINFO_GET_HIGHER_ARITY(type_info);
                        incr_saved_hp(LVALUE_CAST(Word, new_type_info),
                                arity + 2);
                        new_type_info[0] = (Word) type_ctor_info;
                        new_type_info[1] = arity;
                        offset = 2;
                } else {
                        arity = MR_TYPE_CTOR_INFO_GET_TYPE_ARITY(type_ctor_info);
                        incr_saved_hp(LVALUE_CAST(Word, new_type_info),
                                arity + 1);
                        new_type_info[0] = (Word) type_ctor_info;
                        offset = 1;
                }
                for (i = offset; i < arity + offset; i++) {
                        new_type_info[i] = (Word) copy_type_info(&type_info[i],
                                lower_limit, upper_limit);
                }
                leave_forwarding_pointer(type_info_ptr, (Word) new_type_info);
                return new_type_info;
        } else {
                found_forwarding_pointer(type_info);
                return type_info;
        }
}
