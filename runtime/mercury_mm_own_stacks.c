/*
** vim: ts=4 sw=4 expandtab
*/
/*
** Copyright (C) 2004 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** This module contains the functions related specifically to the own stack
** style of minimal model tabling.
*/

#include "mercury_imp.h"
#include "mercury_array_macros.h"
#include "mercury_tabling.h"
#include "mercury_mm_own_stacks.h"

#include <stdio.h>

#ifdef  MR_USE_MINIMAL_MODEL_OWN_STACKS

static  void    make_gen_follow_leader(MR_Generator *this_follower,
                    MR_Generator *leader);

/*---------------------------------------------------------------------------*/

/*
** This part of the file maintains data structures that can be used
** to debug minimal model tabling. It does so by allowing the debugger
** to refer to tabling data structures such as subgoals and consumers
** by small, easily remembered numbers, not memory addresses.
*/

/* set by MR_trace_event, used by table_nondet_setup */
const MR_Proc_Layout          *MR_subgoal_debug_cur_proc = NULL;

struct MR_ConsDebug_Struct
{
    MR_Consumer     *MR_cod_consumer;
    int             MR_cod_sequence_num;
    int             MR_cod_version_num;
    int             MR_cod_valid;
};

struct MR_GenDebug_Struct
{
    MR_Generator    *MR_gd_generator;
    int             MR_gd_sequence_num;
    int             MR_gd_version_num;
    int             MR_gd_valid;
};

#define MR_CONS_DEBUG_INIT      10
#define MR_GEN_DEBUG_INIT       10
#define MR_NAME_BUF             1024

static  MR_ConsDebug    *MR_cons_debug_infos = NULL;
static  int             MR_cons_debug_info_next = 0;
static  int             MR_cons_debug_info_max  = 0;

static  MR_GenDebug     *MR_gen_debug_infos = NULL;
static  int             MR_gen_debug_info_next = 0;
static  int             MR_gen_debug_info_max  = 0;

void
MR_enter_cons_debug(MR_Consumer *consumer)
{
    int i;

    for (i = 0; i < MR_cons_debug_info_next; i++) {
        if (MR_cons_debug_infos[i].MR_cod_consumer == consumer) {
            MR_cons_debug_infos[i].MR_cod_version_num++;
            MR_cons_debug_infos[i].MR_cod_valid = MR_TRUE;
            return;
        }
    }

    MR_ensure_room_for_next(MR_cons_debug_info, MR_ConsDebug,
        MR_CONS_DEBUG_INIT);
    i = MR_cons_debug_info_next;
    MR_cons_debug_infos[i].MR_cod_consumer = consumer;
    MR_cons_debug_infos[i].MR_cod_sequence_num = i;
    MR_cons_debug_infos[i].MR_cod_version_num = 0;
    MR_cons_debug_infos[i].MR_cod_valid = MR_TRUE;
    MR_cons_debug_info_next++;
}

MR_ConsDebug *
MR_lookup_cons_debug_addr(MR_Consumer *consumer)
{
    int i;

    for (i = 0; i < MR_cons_debug_info_next; i++) {
        if (MR_cons_debug_infos[i].MR_cod_consumer == consumer) {
            return &MR_cons_debug_infos[i];
        }
    }

    return NULL;
}

MR_ConsDebug *
MR_lookup_cons_debug_num(int cons_index)
{
    int i;

    for (i = 0; i < MR_cons_debug_info_next; i++) {
        if (MR_cons_debug_infos[i].MR_cod_sequence_num == cons_index) {
            return &MR_cons_debug_infos[i];
        }
    }

    return NULL;
}

const char *
MR_cons_debug_name(MR_ConsDebug *cons_debug)
{
    const char  *warning;
    char        buf[MR_NAME_BUF];

    if (cons_debug == NULL) {
        return "unknown";
    }

    if (cons_debug->MR_cod_valid) {
        warning = "";
    } else {
        warning = " INVALID";
    }

    if (cons_debug->MR_cod_version_num > 0) {
        sprintf(buf, "con %d/%d (%p)%s", cons_debug->MR_cod_sequence_num,
            cons_debug->MR_cod_version_num,
            cons_debug->MR_cod_consumer, warning);
    } else {
        sprintf(buf, "con %d (%p)%s", cons_debug->MR_cod_sequence_num,
            cons_debug->MR_cod_consumer, warning);
    }

    return strdup(buf);
}

const char *
MR_cons_addr_name(MR_Consumer *consumer)
{
    MR_ConsDebug *cons_debug;

    if (consumer == NULL) {
        return "NULL";
    }

    cons_debug = MR_lookup_cons_debug_addr(consumer);
    return MR_cons_debug_name(cons_debug);
}

const char *
MR_cons_num_name(int cons_index)
{
    MR_ConsDebug *cons_debug;

    cons_debug = MR_lookup_cons_debug_num(cons_index);
    return MR_cons_debug_name(cons_debug);
}

void
MR_enter_gen_debug(MR_Generator *generator)
{
    int i;

    for (i = 0; i < MR_gen_debug_info_next; i++) {
        if (MR_gen_debug_infos[i].MR_gd_generator == generator) {
            MR_gen_debug_infos[i].MR_gd_version_num++;
            MR_gen_debug_infos[i].MR_gd_valid = MR_TRUE;
            return;
        }
    }

    MR_ensure_room_for_next(MR_gen_debug_info, MR_GenDebug,
        MR_GEN_DEBUG_INIT);
    i = MR_gen_debug_info_next;
    MR_gen_debug_infos[i].MR_gd_generator = generator;
    MR_gen_debug_infos[i].MR_gd_sequence_num = i;
    MR_gen_debug_infos[i].MR_gd_version_num = 0;
    MR_gen_debug_infos[i].MR_gd_valid = MR_TRUE;
    MR_gen_debug_info_next++;
}

MR_GenDebug *
MR_lookup_gen_debug_addr(MR_Generator *generator)
{
    int i;

    for (i = 0; i < MR_gen_debug_info_next; i++) {
        if (MR_gen_debug_infos[i].MR_gd_generator == generator) {
            return &MR_gen_debug_infos[i];
        }
    }

    return NULL;
}

MR_GenDebug *
MR_lookup_gen_debug_num(int gen_index)
{
    int i;

    for (i = 0; i < MR_gen_debug_info_next; i++) {
        if (MR_gen_debug_infos[i].MR_gd_sequence_num == gen_index) {
            return &MR_gen_debug_infos[i];
        }
    }

    return NULL;
}

const char *
MR_gen_debug_name(MR_GenDebug *gen_debug)
{
    const char  *warning;
    char        buf[MR_NAME_BUF];

    if (gen_debug == NULL) {
        return "unknown";
    }

    if (gen_debug->MR_gd_valid) {
        warning = "";
    } else {
        warning = " INVALID";
    }

    if (gen_debug->MR_gd_version_num > 0) {
        sprintf(buf, "sub %d/%d (%p)%s", gen_debug->MR_gd_sequence_num,
            gen_debug->MR_gd_version_num,
            gen_debug->MR_gd_generator, warning);
    } else {
        sprintf(buf, "sub %d (%p)%s", gen_debug->MR_gd_sequence_num,
            gen_debug->MR_gd_generator, warning);
    }

    return strdup(buf);
}

const char *
MR_gen_addr_name(MR_Generator *generator)
{
    MR_GenDebug *gen_debug;

    if (generator == NULL) {
        return "NULL";
    }

    gen_debug = MR_lookup_gen_debug_addr(generator);
    return MR_gen_debug_name(gen_debug);
}

const char *
MR_gen_num_name(int gen_index)
{
    MR_GenDebug *gen_debug;

    gen_debug = MR_lookup_gen_debug_num(gen_index);
    return MR_gen_debug_name(gen_debug);
}

void
MR_print_gen_debug(FILE *fp, const MR_Proc_Layout *proc,
    MR_GenDebug *gen_debug)
{
    if (gen_debug == NULL) {
        fprintf(fp, "NULL gen_debug\n");
    } else {
        MR_print_generator(fp, proc, gen_debug->MR_gd_generator);
    }
}

void
MR_print_generator(FILE *fp, const MR_Proc_Layout *proc,
    MR_Generator *generator)
{
    MR_SubgoalList  follower;
    MR_ConsumerList consumer;
    MR_AnswerList   answer_list;
    MR_Word         *answer;
    int             answer_num;

    if (generator == NULL) {
        fprintf(fp, "NULL generator\n");
        return;
    }

#ifdef  MR_TABLE_DEBUG
    if (proc == NULL && generator->MR_sg_proc_layout != NULL) {
        proc = generator->MR_sg_proc_layout;
    }
#endif

    fprintf(fp, "generator %s", MR_gen_addr_name(generator));
    if (generator->MR_gen_back_ptr == NULL) {
        fprintf(fp, ", DELETED");
    }
    fprintf(fp, "\n");

    if (proc != NULL) {
        fprintf(fp, "proc: ");
        MR_print_proc_id(fp, proc);
        fprintf(fp, "\n");
    }

#if 0
    fprintf(fp, "leader: %s, ",
        MR_gen_addr_name(generator->MR_sg_leader));
    fprintf(fp, "followers:");
    for (follower = generator->MR_sg_followers;
        follower != NULL; follower = follower->MR_sl_next)
    {
        fprintf(fp, " %s", MR_gen_addr_name(follower->MR_sl_item));
    }

    fprintf(fp, "\nconsumers:");
    for (consumer = generator->MR_sg_cons_list;
        consumer != NULL; consumer = consumer->MR_cl_next)
    {
        fprintf(fp, " %s", MR_cons_addr_name(consumer->MR_cl_item));
    }

    fprintf(fp, "\n");
    fprintf(fp, "answers: %d\n", generator->MR_sg_num_ans);

    if (proc != NULL) {
        answer_list = generator->MR_sg_answer_list;
        answer_num = 1;
        while (answer_list != NULL) {
            fprintf(fp, "answer #%d: <", answer_num);
            MR_print_answerblock(fp, proc, answer_list->MR_aln_answer_block);
            fprintf(fp, ">\n");
            answer_list = answer_list->MR_aln_next_answer;
            answer_num++;
        }
    }
#endif
}

void
MR_print_cons_debug(FILE *fp, const MR_Proc_Layout *proc,
    MR_ConsDebug *cons_debug)
{
    if (cons_debug == NULL) {
        fprintf(fp, "NULL cons_debug\n");
    } else {
        MR_print_consumer(fp, proc, cons_debug->MR_cod_consumer);
    }
}

void
MR_print_consumer(FILE *fp, const MR_Proc_Layout *proc, MR_Consumer *consumer)
{
    if (consumer == NULL) {
        fprintf(fp, "NULL consumer\n");
        return;
    }

    fprintf(fp, "consumer %s", MR_cons_addr_name(consumer));

    /* XXX check semantics of DELETED */
    if (consumer->MR_cons_answer_generator == NULL) {
        fprintf(fp, ", DELETED\n");
    } else {
        fprintf(fp, ", answer generator %s",
            MR_gen_addr_name(consumer->MR_cons_answer_generator));
        if (consumer->MR_cons_containing_generator != NULL) {
            fprintf(fp, ", in generator %s\n",
                MR_gen_addr_name(consumer->MR_cons_answer_generator));
        } else {
            fprintf(fp, ", in main context\n\n");
        }
        fprintf(fp, "returned answers %d, remaining answers ptr %p\n",
            consumer->MR_cons_num_returned_answers,
            consumer->MR_cons_remaining_answer_list_ptr);
    }
}

/*---------------------------------------------------------------------------*/

static  int MR_next_gen_context = 1;

static MR_Context *
MR_get_context_for_gen(MR_Generator *gen)
{
    MR_Dlist        *list;
    MR_Dlist        *item;
    MR_Context      *ctxt;

    list = MR_ENGINE(MR_eng_free_contexts);
    if (MR_dlist_length(list) > 0) {
        item = MR_dlist_first_ptr(list);
        ctxt = (MR_Context *) MR_dlist_data(item);
        MR_dlist_delete(list, item, NULL);
    } else {
        char    buf[80];    /* ought to be plenty big enough */

        sprintf(buf, "gen%d", MR_next_gen_context);
        MR_next_gen_context++;
        ctxt = MR_create_context(strdup(buf), gen);
    }

    ctxt->MR_ctxt_owner_generator = gen;
    return ctxt;
}

MR_ConsumerPtr
MR_table_setup_consumer(MR_TableNode trie_node, MR_Integer num_input_args,
    MR_Word *generator_pred, MR_String pred_id)
{
    /* not yet implemented */
}

MR_Generator *
MR_setup_generator(MR_String pred_id, MR_TrieNode trie_node)
{
    /*
    ** Initialize the generator if this is the first time we see it.
    ** If the subgoal structure already exists but is marked inactive,
    ** then it was left by a previous generator that couldn't
    ** complete the evaluation of the subgoal due to a commit.
    ** In that case, we want to forget all about the old generator.
    */

    MR_restore_transient_registers();
#if 0
    if (trie_node->MR_generator == NULL) {
        MR_Generator *gen;
        MR_Context   *context;

        gen = MR_TABLE_NEW(MR_Generator);
        context = MR_get_context_for_gen(gen);

        gen->MR_gen_back_ptr = trie_node;
        gen->MR_gen_context = context;
        gen->MR_gen_leader = gen;
        gen->MR_gen_led_generators = MR_dlist_makelist(gen);
        gen->MR_gen_consumers = MR_dlist_makelist0();
        gen->MR_gen_num_answers = 0;
        gen->MR_gen_answer_table.MR_integer = 0;
        gen->MR_gen_answer_list = NULL;
        gen->MR_gen_answer_list_tail = &gen->MR_gen_answer_list;

        /*
        ** MR_subgoal_debug_cur_proc refers to the last procedure
        ** that executed a call event, if any. If the procedure that is
        ** executing table_nondet_setup is traced, this will be that
        ** procedure, and recording the layout structure of the
        ** processor in the generator allows us to interpret the contents
        ** of the generator's answer tables. If the procedure executing
        ** table_nondet_setup is not traced, then the layout structure
        ** belongs to another procedure and the any use of the
        ** MR_gen_proc_layout field will probably cause a core dump.
        ** For implementors debugging minimal model tabling, this is
        ** the right tradeoff.
        */
        gen->MR_gen_proc_layout = MR_subgoal_debug_cur_proc;

#ifdef  MR_TABLE_DEBUG
        MR_enter_gen_debug(gen);

        if (MR_tabledebug) {
            printf("setting up generator %p -> %s, ",
                trie_node, MR_gen_addr_name(gen));
            printf("answer slot %p\n", subgoal->MR_sg_answer_list_tail);
            if (subgoal->MR_gen_proc_layout != NULL) {
                printf("proc: ");
                MR_print_proc_id(stdout, gen->MR_gen_proc_layout);
                printf("\n");
            }
        }

        if (MR_maxfr != MR_curfr) {
            MR_fatal_error("MR_maxfr != MR_curfr at table setup\n");
        }
#endif
        trie_node->MR_generator = gen;
    }

#endif
    return trie_node->MR_generator;
    MR_save_transient_registers();
}

MR_AnswerBlock
MR_table_consumer_get_next_answer(MR_ConsumerPtr consumer)
{
    /* not yet implemented */
}

MR_TrieNode
MR_table_generator_get_answer_table(MR_GeneratorPtr generator)
{
    /* not yet implemented */
}

MR_TrieNode
MR_table_generator_new_answer_slot(MR_GeneratorPtr generator)
{
    /* not yet implemented */
}

#endif  /* MR_USE_MINIMAL_MODEL_OWN_STACKS */