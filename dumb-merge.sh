#!/bin/sh
# Simple-stupid extract and merge script.

# Setup basics
REPO_LIST_FILE="repos.list"
REPO_SRC_ROOT="../source-trees"
REPO_DEST_ROOT="../temptorsent-dest-trees"
REPO_DEST_PATCHES="${REPO_DEST_ROOT}/patchsets"

mkdir -p "${REPO_SRC_ROOT}"
mkdir -p "${REPO_DEST_PATCHES}"

# Setup a repo if it doesn't exist.
src_repo_setup() {
	local repo_name="$(get_reporef_name "${1}")"
	local repo_root="$(get_repo_root "${repo_name}")"
	local repo_uri="$(get_repo_uri "${repo_name}")"
	if ! [ -d "${repo_root}" ] ; then
		mkdir -p "${repo_root%/*}"
		git clone "${repo_uri}" "${repo_root}"
	else
		: # echo "To update gentoo repo: cd ../source-trees/gentoo && git pull"
	fi
}

# reporef format <reponame>[/<path/under/git/root>][@<git-commit-ref>]

# Get just the repo name, hacking off any path passed after it.
get_reporef_name() { local n="${1%@*}" ; printf -- "${n%%/*}" ; }

# Get just the subdir under the repo-root, if given.
get_reporef_subdir() { local s="${1%@*}" ; [ "${s}" == "${s#*/}" ] || printf -- "${s#*/}" ; }

# Get just the git-ref (commit/tag/etc) under the repo-root, if given, follows @ sign. Default to 'master' if none given.
get_reporef_gitref() { [ "${1}" == "${1##*@}}" ] && printf -- "master" || printf -- "${1##*@}" ; }

# Get a full path in the repo.
get_reporef_path() {
	local repo_root="$(get_repo_root "${1}")"
	local repo_subdir="$(get_reporef_subdir "${1}")"
	printf -- "${repo_root}${repo_subdir:+/${repo_subdir}}"
}

# Get the repo root, prefix relative paths with ${REPO_SRC_ROOT}
get_repo_root() {
	local repo_name="$(get_reporef_name "${1}")"
	local repo_root="$(get_repo_field "${repo_name}" "root")"
	case "${repo_root}" in
		"."/*|".."/*|"/"*) printf -- "${repo_root}" ;;
		[_[:alnum:]]*) printf -- "${REPO_SRC_ROOT}/${repo_root}" ;;
		*) return 1 ;;
	esac
}


# Get the uri for the repo.
get_repo_uri() { get_repo_field "${1}" "uri" ; }

# Get the value of the requested field from the ${REPO_LIST_FILE}
get_repo_field() {
	local repo_name="$(get_reporef_name "${1}")"
	field_name="${2}"
	case "${field_name}" in
		name) field_num=1;;
		root) field_num=2;;
		uri) field_num=3;;
		*) echo "Bad field: '${field_name}' for repo '${repo_name}'! Should be 'nane', 'root', or 'uri'." ; return 1 ;;
	esac
	awk '$1=="'"${repo_name}"'" { print $'"${field_num}"' }' "${REPO_LIST_FILE}"
}

# Extract a patchset against the specified reporef for the files matched by the regex passed as the remaining args.
src_repo_patchset() {
	local repo_name="$(get_reporef_name ${1})"
	local repo_subdir="$(get_reporef_subdir ${1})"
	local git_ref="$(get_reporef_gitref ${1})"
	local repo_root="$(get_repo_root "${repo_name}")"
	local patchfile="${2}"
	shift 2
	local patterns="$@"
	(set -f ; cd "${repo_root}${repo_subdir:+/${repo_subdir}}" && git log --pretty=email --patch-with-stat --reverse --full-index --binary ${git_ref} -- ${patterns} ) >> "${patchfile}"
}


# Load list of kits to generate
while read -r mykit; do
	case "${mykit}" in
		"#"*) : ;;
		[_[:alnum:]]*) KITLIST="${KITLIST:+${KITLIST} }${mykit}" ;;
	esac
done < kit.list

for mykit in ${KITLIST} ; do
	ALLREPOREFS=""
	REPOREFS=""
	allregex=""

	# Local function, needs to be called in scope of main loop.
	do_extract_patches() {
		[ -n "${REPOREFS_LAST}" ] && [ -n "${allregex}" ] || return
		for myrr in ${REPOREFS_LAST} ; do
			local myreponame="$(get_reporef_name "${myrr}")"
			local myreposubdir="$(get_reporef_subdir "${myrr}")"
			local myreposubdir_="$(printf -- "${myreposubdir}" | tr '/' '_')"
			local myrepogitref="$(get_reporef_gitref "${myrr}")"

			# This gives a filename that should be unique to reporef unless there is some crazy '_' action going on in paths.
			local mypatch="${REPO_DEST_PATCHES}/${mykit}-${myreponame}${myreposubdir_:+_${myreposubdir_}}@${myrepogitref}.patch"

			# Give the user an idea what's going on ;)
			printf -- "\nExtracting patchset for '${mykit}' from '${myrr}' to '${mypatch}'"

			# If we haven't seen this reporef before, wipe the patch and start fresh.
			( printf -- "${ALLREPOREFS}" | grep -qw "${myrr}[^/@]" ) && printf -- ".\n" || ( printf -- "" > "${mypatch}" && printf -- " (Cleared old).\n")

			# If we haven't seen this repo yet, set it up.
			( printf -- "${ALLREPOREFS}" | grep -qw "${myrr}" ) || src_repo_setup "${myreponame}"


			# Extract this set of patches
			printf -- "Selecting files in repo under '$(get_reporef_path ${myrr})' matching regex:\n\n"
			printf -- "${allregex}" | tr ' ' '\n' | column -t
			printf -- "\n"
			src_repo_patchset "${myrr}" "${mypatch}" "${allregex}"
			printf -- "...done...\n\n"
			# Add this reporef to the list of all we've seen
			ALLREPOREFS="${ALLREPOREFS:+${ALLREPOREFS} }${myrr}"
		done
	}

	REPOREFS_TOK="#REPOREFS="
	while read -r myregex; do
		case "${myregex}" in
			"${REPOREFS_TOK}"*)
				# If we're going to swtich to a new repo, we need to generate the patchset for the last one before we change anything.
				REPOREFS_LAST="${REPOREFS}"
				REPOREFS="${myregex#"${REPOREFS_TOK}"}"
				do_extract_patches && allregex=""
			;;
			"#"*) : ;;
			[a-z]*) allregex="${allregex} ${myregex}" ;;
		esac
	done < "${mykit}.kit"

	# We found the end of the file.
	# Process the last set of reporefs seen with the current ${allregex} value.
	REPOREFS_LAST="${REPOREFS}"
	REPOREFS=""
	do_extract_patches

done


