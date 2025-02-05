[SharedVariables::] Shared Variables.

Shared variables are held in common by all rules working in some goal.

@h Introduction.
Inform allows some variables to be shared by a number of different rules
(with different stack frames) and yet not be global in scope or permanent
in existence: they are shared by some process carried out by rulebooks.

The semantics of shared variables are unusual because rules can be
in multiple rulebooks, or can be moved out of their expected rulebooks.
Their names are therefore not limited in scope -- they are global, and
they belong to the same namespace as global variables. But access to them
is restricted to just those rules with permission.

Each //shared_variable// belongs to just one //shared_variable_set//, but the
code forming the body of a rule may be able to access multiple sets. So
each stack frame has its own //shared_variable_access_list// of those sets
which it can see.

@h Variables.
As can be seen, a shared variable is really just some additional expectations
placed on a nonlocal variable (for which, see //knowledge: Nonlocal Variables//):

=
typedef struct shared_variable {
	struct shared_variable_set *owner; /* who owns this */
	int index_in_owner; /* counting upwards from 0 */
	struct wording name; /* text of the name */
	struct parse_node *assigned_at; /* sentence creating the variable */
	struct nonlocal_variable *underlying_var; /* the variable in question */
	struct wording match_wording_text; /* matching text (relevant for action variables only) */
	int is_actor; /* set only for the special "actor" variable */
	CLASS_DEFINITION
} shared_variable;

@ And it can only be created within a set:

=
shared_variable *SharedVariables::new(shared_variable_set *set, wording W, kind *K,
	int is_actor) {
	shared_variable *shv = CREATE(shared_variable);
	W = Articles::remove_the(W);
	shv->name = W;
	shv->owner = set;
	shv->index_in_owner = LinkedLists::len(set->variables);
	shv->assigned_at = current_sentence;
	shv->match_wording_text = EMPTY_WORDING;
	nonlocal_variable *nlv = NonlocalVariables::new(W, K, shv);
	shv->underlying_var = nlv;
	shv->is_actor = is_actor;
	RTVariables::tie_NLV_to_shared_variable(nlv, shv);
	SharedVariables::add_to_set(shv, set);
	return shv;
}

@ Some miscellaneous access functions:

=
inter_name *SharedVariables::get_owner_iname(shared_variable *shv) {
	return shv->owner->recognition_iname;
}

int SharedVariables::get_index(shared_variable *shv) {
	return shv->index_in_owner;
}

kind *SharedVariables::get_kind(shared_variable *shv) {
	nonlocal_variable *nlv = SharedVariables::get_variable(shv);
	return NonlocalVariables::kind(nlv);
}

nonlocal_variable *SharedVariables::get_variable(shared_variable *shv) {
	if (shv == NULL) return NULL;
	return shv->underlying_var;
}

int SharedVariables::is_actor(shared_variable *shv) {
	if (shv == NULL) return FALSE;
	return shv->is_actor;
}

@ The match text associated with a shared variable is used in parsing action
patterns: see //if: Action Name Lists//. But for most shared variables, this
text remains empty.

=
void SharedVariables::set_matching_text(shared_variable *shv, wording W) {
	shv->match_wording_text = W;
}

wording SharedVariables::get_matching_text(shared_variable *shv) {
	return shv->match_wording_text;
}

@h Sets.
Sets are identified by an identifier which will be defined during linking so
that it is unique among all variable sets in the executable.

=
typedef struct shared_variable_set {
	struct inter_name *recognition_iname;
	struct linked_list *variables; /* of |shared_variable| */
	CLASS_DEFINITION
} shared_variable_set;

shared_variable_set *SharedVariables::new_set(inter_name *iname) {
	shared_variable_set *set = CREATE(shared_variable_set);
	set->recognition_iname = iname;
	set->variables = NEW_LINKED_LIST(shared_variable);
	return set;
}

int SharedVariables::set_empty(shared_variable_set *set) {
	if (set == NULL) return TRUE;
	if (LinkedLists::len(set->variables) == 0) return TRUE;
	return FALSE;
}

int size_of_largest_set = 0;

void SharedVariables::add_to_set(shared_variable *shv, shared_variable_set *set) {
	ADD_TO_LINKED_LIST(shv, shared_variable, set->variables);
	if (LinkedLists::len(set->variables) > size_of_largest_set)
		size_of_largest_set = LinkedLists::len(set->variables);
}

int SharedVariables::size_of_largest_set(void) {
	return size_of_largest_set;
}

@ Returns the first variable in the set whose matching text begins |W|. Note
that this requires the match text to be nonempty, so it can only return
variables which have one.

=
shared_variable *SharedVariables::parse_match_clause(shared_variable_set *set,
	wording W) {
	shared_variable *shv;
	LOOP_OVER_LINKED_LIST(shv, shared_variable, set->variables)
		if (Wordings::starts_with(W, shv->match_wording_text))
			return shv;
	return NULL;
}

@h Access lists.
These could hardly be simpler:

=
typedef struct shared_variable_access_list {
	struct linked_list *sets; /* of |shared_variable_set| */
	CLASS_DEFINITION
} shared_variable_access_list;

shared_variable_access_list *SharedVariables::new_access_list(void) {
	shared_variable_access_list *nshvol = CREATE(shared_variable_access_list);
	nshvol->sets = NEW_LINKED_LIST(shared_variable_set);
	return nshvol;
}

@ Duplicates are not allowed:

=
void SharedVariables::add_set_to_access_list(shared_variable_access_list *access,
	shared_variable_set *set) {
	if (access) {
		shared_variable_set *existing;
		LOOP_OVER_LINKED_LIST(existing, shared_variable_set, access->sets)
			if (existing == set)
				return;
		ADD_TO_LINKED_LIST(set, shared_variable_set, access->sets);
	}
}

@ This changes |access| to the union of |access| and |extras|:

=
void SharedVariables::append_access_list(shared_variable_access_list *access,
	shared_variable_access_list *extras) {
	shared_variable_set *set;
	if ((extras) && (access))
		LOOP_OVER_LINKED_LIST(set, shared_variable_set, extras->sets)
			SharedVariables::add_set_to_access_list(access, set);
}

@ Returns the first shared variable of the given name |W| in any set in the
access list. This would be inefficient if access lists were ever large, or
if individual sets were, but they are not. Giving each access list its own
associative hash would make little or no saving of time, and would decrease
the predictability of results.

=
shared_variable *SharedVariables::parse_from_access_list(shared_variable_access_list *access,
	wording W) {
	if (Wordings::empty(W)) return NULL;
	W = Articles::remove_the(W);
	shared_variable_set *set;
	if (access)
		LOOP_OVER_LINKED_LIST(set, shared_variable_set, access->sets) {
			shared_variable *shv;
			LOOP_OVER_LINKED_LIST(shv, shared_variable, set->variables)
				if (Wordings::match(shv->name, W))
					return shv;
		}
	return NULL;
}
