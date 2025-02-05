[PhraseOptions::] Phrase Options.

To create and subsequently parse against the list of phrase options
with which the user can choose to invoke a To phrase.

@h Introduction.
A "phrase option" is a sort of modifier tacked on to an invocation of a
phrase; the only modifiers allowed are those declared in that phrase's
preamble. Phrase pptions are an early feature of Inform 7 going back to a
time when its priority was to enable the paraphrasing of Inform 6 library
features (such as the bitmap passed as a parameter to the list-printer).

I now sligjtly regret the existence of phrase options, but above all the
comma-based syntax used for them, as here. Brackets would have been better;
it makes phrase options impossible to use for text substitutions.

>> let R be the best route from X to Y, using doors;

I sometimes even regret the existence of phrase options, but it must be
admitted that they are a clean way to interface to low-level Inform 6 code.
But it's mostly the comma which annoys me (making text substitutions unable
to support phrase options); I should have gone for brackets.

The //id_options_data// for an imperative definition, which is part of its
type data, says what options it allows:

@d MAX_OPTIONS_PER_PHRASE 16 /* because held in a 16-bit Z-machine bitmap */

=
typedef struct id_options_data {
	struct phrase_option *options_permitted[MAX_OPTIONS_PER_PHRASE];
	int no_options_permitted;
	struct wording options_declaration; /* the text declaring the whole set of options */
	int multiple_options_permitted; /* can be combined, or mutually exclusive? */
} id_options_data;

typedef struct phrase_option {
	struct wording name; /* text of name */
} phrase_option;

@h Creation.
By default, a phrase has no options.

=
id_options_data PhraseOptions::new(wording W) {
	id_options_data phod;
	phod.no_options_permitted = 0;
	phod.multiple_options_permitted = FALSE;
	phod.options_declaration = W;
	return phod;
}

int PhraseOptions::allows_options(id_body *idb) {
	id_options_data *phod = &(idb->type_data.options_data);
	if (phod->no_options_permitted > 0) return TRUE;
	return FALSE;
}

@ =
int PM_TooManyPhraseOptions_issued = FALSE;
void PhraseOptions::phod_add_phrase_option(id_options_data *phod, wording W) {
	LOGIF(PHRASE_CREATIONS, "Adding phrase option <%W>\n", W);
	if (phod->no_options_permitted >= MAX_OPTIONS_PER_PHRASE) {
		if (PM_TooManyPhraseOptions_issued == FALSE)
			StandardProblems::sentence_problem(Task::syntax_tree(),
				_p_(PM_TooManyPhraseOptions),
				"a phrase is only allowed to have 16 different options",
				"so either some of these will need to go, or you may want to consider "
				"breaking up the phrase into simpler ones whose usage is easier to describe.");
		PM_TooManyPhraseOptions_issued = TRUE;
		return;
	}
	PM_TooManyPhraseOptions_issued = FALSE; /* so the problem can recur on later phrases */

	phrase_option *po = CREATE(phrase_option);
	po->name = W;
	phod->options_permitted[phod->no_options_permitted++] = po;
}

@h Parsing.
This isn't very efficient, but doesn't need to be, since phrase options are parsed
only in a condition context, not in a value context, and these are relatively
rare in Inform source text.

=
id_options_data *phod_being_parsed = NULL;
id_body *idb_being_parsed = NULL;

int PhraseOptions::parse_phod(id_options_data *phod, wording W) {
	for (int i = 0; i < phod->no_options_permitted; i++)
		if (Wordings::match(W, phod->options_permitted[i]->name))
			return (1 << i);
	return -1;
}
int PhraseOptions::parse(id_body *idb, wording W) {
	return PhraseOptions::parse_phod(&(idb->type_data.options_data), W);
}

@ Which we wrap up thus:

=
<phrase-option> internal {
	int bitmap = PhraseOptions::parse_phod(phod_being_parsed, W);
	if (bitmap == -1) { ==> { fail nonterminal }; }
	==> { bitmap, - };
	return TRUE;
}

@h Parsing phrase options in a declaration.
The following is called with |W| set to just the part of a phrase prototype
containing its phrase options. In this example:
= (text as Inform 7)
To decide which object is best route from (R1 - object) to (R2 - object),
	using doors or using even locked doors:
=
|W| would be "using doors or using even locked doors".

The syntax is just a list of names, but with the wrinkle that if the list is divided
with "or" then the options are mutually exclusive, but with "and/or" they're not.
	
=
void PhraseOptions::parse_declared_options(id_options_data *phod, wording W) {
	if (Wordings::nonempty(W)) {
		phod->options_declaration = W;
		phod_being_parsed = phod;
		<phrase-option-decl-list>(W);
		if (<<r>>) phod->multiple_options_permitted = TRUE;
	}
}

@ Note the following Preform grammar passes the return value |TRUE| up from
the final element of the list when the connective used for it was "and/or".
Note also the rare use of the Preform literal marker in |\and/or| to show
that the slash between "and" and "or" is part of the word.

=
<phrase-option-decl-list> ::=
	... |                                                           ==> { lookahead }
	<phrase-option-decl-setting-entry> <phrase-option-decl-tail> |  ==> { pass 2 }
	<phrase-option-decl-setting-entry>                              ==> { FALSE, - }

<phrase-option-decl-tail> ::=
	, _or <phrase-option-decl-list> |                               ==> { pass 1 }
	, \and/or <phrase-option-decl-list> |                           ==> { TRUE, - }
	_,/or <phrase-option-decl-list> |                               ==> { pass 1 }
	\and/or <phrase-option-decl-list>                               ==> { TRUE, - }

<phrase-option-decl-setting-entry> ::=
	... |                                                           ==> { lookahead }
	...                                                             ==> @<Add a phrase option@>;
	
@<Add a phrase option@> =
	PhraseOptions::phod_add_phrase_option(phod_being_parsed, W);
	==> { FALSE, - };

@h Parsing phrase options in an invocation.
At this point, we're looking at the text after the first comma in something
like:

>> list the contents of the box, as a sentence, with newlines;

The invocation has already been parsed enough that we know the options
chosen are:

>> as a sentence, with newlines

and the following routine turns that into a bitmap with two bits set, one
corresponding to each choice.

We return |TRUE| or |FALSE| according to whether the options were valid or
not, and the |silently| flag suppresses problem messages we would otherwise
produce.

=
int phod_being_parsed_silently = FALSE; /* context for the grammar below */

int PhraseOptions::parse_invoked_options(parse_node *inv, int silently) {
	id_body *idb = Node::get_phrase_invoked(inv);
	wording W = Invocations::get_phrase_options(inv);

	idb_being_parsed = idb;
	phod_being_parsed = &(idb_being_parsed->type_data.options_data);

	int bitmap = 0;
	int pc = problem_count;
	@<Parse the supplied list of options into a bitmap@>;

	Invocations::set_phrase_options_bitmap(inv, bitmap);
	if (problem_count > pc) return FALSE;
	return TRUE;
}

@<Parse the supplied list of options into a bitmap@> =
	int s = phod_being_parsed_silently;
	phod_being_parsed_silently = silently;
	if (<phrase-option-list>(W)) bitmap = <<r>>;
	phod_being_parsed_silently = s;

	if ((problem_count == pc) &&
		(phod_being_parsed->multiple_options_permitted == FALSE))
		@<Reject this if multiple options are set@>;

@ Ah, bit-twiddling: fun for all the family. There's no point computing the
population count of the bitmap, that is, the number of bits set: we only need
to know if it's a power of 2 or not. Note that subtracting 1, in binary,
clears the least significant set bit, leaves the higher bits as they are,
and changes the lower bits (which were previously all 0s) to 1s. So taking
a bitwise-and of a number and itself minus one leaves just the higher bits
alone. The original number therefore had a single set bit if and only if
this residue is zero.

@<Reject this if multiple options are set@> =
	if ((bitmap & (bitmap - 1)) != 0) {
		if (silently == FALSE) {
			Problems::quote_source(1, current_sentence);
			Problems::quote_wording(2, W);
			Problems::quote_phrase(3, idb);
			Problems::quote_wording(4, phod_being_parsed->options_declaration);
			StandardProblems::handmade_problem(Task::syntax_tree(),
				_p_(PM_PhraseOptionsExclusive));
			Problems::issue_problem_segment(
				"You wrote %1, supplying the options '%2' to the phrase '%3', but "
				"the options listed for this phrase ('%4') are mutually exclusive.");
			Problems::issue_problem_end();
		}
		return FALSE;
	}

@ When setting options, in an actual use of a phrase, the list is divided
by "and":

=
<phrase-option-list> ::=
	... |                                                ==> { lookahead }
	<phrase-option-setting-entry> <phrase-option-tail> | ==> { R[1] | R[2], - }
	<phrase-option-setting-entry>                        ==> { pass 1 }

<phrase-option-tail> ::=
	, _and <phrase-option-list> |                        ==> { pass 1 }
	_,/and <phrase-option-list>                          ==> { pass 1 }

<phrase-option-setting-entry> ::=
	<phrase-option> |                                    ==> { pass 1 }
	...  ==> @<Issue PM_NotAPhraseOption or C22NotTheOnlyPhraseOption problem@>

@<Issue PM_NotAPhraseOption or C22NotTheOnlyPhraseOption problem@> =
	if ((!preform_lookahead_mode) && (!phod_being_parsed_silently)) {
		Problems::quote_source(1, current_sentence);
		Problems::quote_wording(2, W);
		Problems::quote_phrase(3, idb_being_parsed);
		Problems::quote_wording(4, phod_being_parsed->options_declaration);
		if (phod_being_parsed->no_options_permitted > 1) {
			StandardProblems::handmade_problem(Task::syntax_tree(),
				_p_(PM_NotAPhraseOption));
			Problems::issue_problem_segment(
				"You wrote %1, but '%2' is not one of the options allowed on "
				"the end of the phrase '%3'. (The options allowed are: '%4'.)");
			Problems::issue_problem_end();
		} else {
			StandardProblems::handmade_problem(Task::syntax_tree(),
				_p_(PM_NotTheOnlyPhraseOption));
			Problems::issue_problem_segment(
				"You wrote %1, but the only option allowed on the end of the "
				"phrase '%3' is '%4', so '%2' is not something I know how to "
				"deal with.");
			Problems::issue_problem_end();
		}
	}
