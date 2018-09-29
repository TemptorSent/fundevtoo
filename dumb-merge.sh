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
	allglobs=""

	# Local function, needs to be called in scope of main loop.
	do_extract_and_merge_patches() {
		# Short-circuit return if we have nothign to do.
		[ -n "${REPOREFS_LAST}" ] && [ -n "${allglobs}" ] || return

		# Setup our paths to store patches and dest git repo
		local mypatchdir="$(realpath "${REPO_DEST_PATCHES}")"
		local mykitgitdir="${REPO_DEST_ROOT}/${mykit}"

		# Wipe our repo dir and start from scratch -- complain if we don't see what we expect.
		if [ -e "${mykitgitdir}" ] ; then
			if [ -d "${mykitgitdir}/.git" ] ; then
				printf -- "Removing old git repo at '${mykitgitdir}'.\n"
				rm -rf "${mykitgitdir}"
			else
				printf -- "'${mykitgitdir}' is not a git repo root, not touching it and bailing!\n"
				exit 1
			fi
		fi
		mkdir -p "${mykitgitdir}"
		( cd "${mykitgitdir}" && git init . && git commit -m "Root Commit for ${mykit}" --allow-empty && git checkout -b merged )

		# Iterate over reporefs on the stack, extract the patches, and apply them to merged branch.
		for myrr in ${REPOREFS_LAST} ; do
			local myreponame="$(get_reporef_name "${myrr}")"
			local myreporoot="$(get_repo_root "${myrr}")"
			local myreposubdir="$(get_reporef_subdir "${myrr}")"
			local myreposubdir_="$(printf -- "${myreposubdir}" | tr '/' '_')"
			local myrepogitref="$(get_reporef_gitref "${myrr}")"

			# Fetch our hash for the git_ref
			local myrepohash="$(cd "${myreporoot}${myreposubdir:+/${myreposubdir}}" && git rev-parse "${myrepogitref}" )"

			# This gives a filename that should be unique to reporef unless there is some crazy '_' action going on in paths.
			local myrepopath_="${myreponame}${myreposubdir_:+_${myreposubdir_}}"
			local mypatch="${mypatchdir}/${mykit}-${myrepopath_}@${myrepogitref}#${myrepohash}.patch"

			# Give the user an idea what's going on ;)
			printf -- "\nExtracting patchset for '${mykit}' from '${myrr}' to '${mypatch}'"

			# If we haven't seen this reporef before, wipe the patch and start fresh.
			( printf -- "${ALLREPOREFS}" | grep -qw "${myrr}[^/@]" ) && printf -- ".\n" || ( printf -- "" > "${mypatch}" && printf -- " (Cleared old).\n")

			# If we haven't seen this repo yet, set it up.
			( printf -- "${ALLREPOREFS}" | grep -qw "${myrr}" ) || src_repo_setup "${myreponame}"


			# Extract this set of patches
			printf -- "Selecting files in repo under '$(get_reporef_path ${myrr})' matching regex:\n\n"
			printf -- "${allglobs}" | tr ' ' '\n' | column -t
			printf -- "\n"
			(	set -f
				cd "${myreporoot}${myreposubdir:+/${myreposubdir}}" \
					&& git log \
						--binary --pretty=email --patch-with-stat --topo-order --reverse --full-index ${myreposubdir:+--relative="${myreposubdir}"} \
						--break-rewrites=40%/70% --find-renames=20% \
						${myrepohash} -- ${allglobs}
			) >> "${mypatch}"
			#src_repo_patchset "${myrr}" "${mypatch}" "${allglobs}"
			printf -- "...done...\n\n"
			# Add this reporef to the list of all we've seen
			ALLREPOREFS="${ALLREPOREFS:+${ALLREPOREFS} }${myrr}"

			# Merge the patch we just generated into our kit's repo`
			pushd "${mykitgitdir}" > /dev/null
				# Give the user an idea what's going on ;)
				printf -- "\nMerging patchset for '${myrr}' from '${mypatch}' to '${mykitgitdir}'"
				# Create new branch for each patcheset
				git checkout master
				git checkout -b "${myrepopath_}"
				# Apply our patchset to that branch
				git am "${mypatch}"
				# Switch to 'merged' branch and attempt to merge our new patcheset branch
				git checkout merged
				git merge --no-commit "${myrepopath_}"
				# Resolve conflicts by always taking the version from the branch being merged in
				git checkout --theirs .
				# Add resoutions and commit.
				git add .
				git commit -m "Merged '${myrepopath_}' branch into 'merged'."
			popd > /dev/null
		done
	}

	REPOREFS_TOK="#REPOREFS="
	while read -r myglob; do
		case "${myglob}" in
			"${REPOREFS_TOK}"*)
				# If we're going to swtich to a new repo, we need to generate the patchset for the last one before we change anything.
				REPOREFS_LAST="${REPOREFS}"
				REPOREFS="${myglob#"${REPOREFS_TOK}"}"
				do_extract_and_merge_patches && allglobs=""
			;;
			"#"*) : ;;
			[a-z]*) allglobs="${allglobs} ${myglob}" ;;
		esac
	done < "${mykit}.kit"

	# We found the end of the file.
	# Process the last set of reporefs seen with the current ${allglobs} value.
	REPOREFS_LAST="${REPOREFS}"
	REPOREFS=""
	do_extract_and_merge_patches

done


