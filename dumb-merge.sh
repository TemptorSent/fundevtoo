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
	local repo_name="$(get_repo_name "${1}")"
	local repo_root="$(get_repo_root "${repo_name}")"
	local repo_uri="$(get_repo_uri "${repo_name}")"
	if ! [ -d "${repo_root}" ] ; then
		mkdir -p "${repo_root%/*}"
		git clone "${repo_uri}" "${repo_root}"
	else
		: # echo "To update gentoo repo: cd ../source-trees/gentoo && git pull"
	fi
}

# Get just the repo name, hacking off any path passed after it.
get_repo_name() { printf -- "${1%%/*}" ; }
# Get just the subdir of the repo, if given.
get_repo_subdir() { [ "${1}" == "${1#*/}" ] || printf -- "${1#*/}" ; }

# Get the repo root, prefix relative paths with ${REPO_SRC_ROOT}
get_repo_root() {
	local repo_root="$(get_repo_field "${1}" "root")"
	case "${repo_root}" in
		"."/*|".."/*|"/"*) printf -- "${repo_root}" ;;
		[_[:alnum:]]*) printf -- "${REPO_SRC_ROOT}/${repo_root}" ;;
		*) return 1 ;;
	esac
}

# Get a full path in the repo.
get_repo_path() {
	local repo_root="$(get_repo_root "${1}")"
	local repo_subdir="$(get_repo_subdir "${1}")"
	printf -- "${repo_root}${repo_subdir:+/${repo_subdir}}"
}

# Get the uri for the repo.
get_repo_uri() { get_repo_field "${1}" "uri" ; }

# Get the value of the requested field from the ${REPO_LIST_FILE}
get_repo_field() {
	local repo_name="$(get_repo_name "${1}")"
	field_name="${2}"
	case "${field_name}" in
		name) field_num=1;;
		root) field_num=2;;
		uri) field_num=3;;
		*) echo "Bad field: '${field_name}' for repo '${repo_name}'! Should be 'nane', 'root', or 'uri'." ; return 1 ;;
	esac
	awk '$1=="'"${repo_name}"'" { print $'"${field_num}"' }' "${REPO_LIST_FILE}"
}

src_repo_patchset() {
	local repo_name="${1}"
	local repo_root="$(get_repo_root "${repo_name}")"
	local git_ref="${2}"
	local patchfile="${3}"
	shift 3
	local patterns="$@"
	(set -f ; cd "${repo_root}" && git log --pretty=email --patch-with-stat --reverse --full-index --binary ${git_ref} -- ${patterns} ) > "${patchfile}"
}


# Load list of kits to generate
while read -r mykit; do
	case "${mykit}" in
		"#"*) : ;;
		[_[:alnum:]]*) KITLIST="${KITLIST:+${KITLIST} }${mykit}" ;;
	esac
done < kit.list

for mykit in ${KITLIST} ; do
	REPO_NAME=""
	REPO_SUBDIR=""
	GIT_REF="master"
	allregex=""

	do_run_patch() { src_repo_patchset "${REPO_NAME_PATCH}${REPO_SUBDIR_PATCH:+/${REPO_SUBDIR_PATCH}}" "${GIT_REF_PATCH}" "${REPO_DEST_PATCHES}/${mykit}-${REPO_NAME_PATCH}-${GIT_REF_PATCH}.patch" "${allregex}" ; }

	while read -r myregex; do
		REPO_NAME_PATCH="${REPO_NAME}"
		REPO_SUBDIR_PATCH="${REPO_SUBDIR}"
		GIT_REF_PATCH="${GIT_REF}"
		case "${myregex}" in
			"#REPO_NAME="*)
				# If we're going to swtich to a new repo, we need to generate the patchset for the last one before we change anything.
				REPO_NAME="${myregex#\#REPO_NAME=}"
				[ -n "${REPO_NAME_PATCH}" ] && [ "${REPO_NAME_PATCH}" != "${REPO_NAME}" ] && run_patch=1
				src_repo_setup "${REPO_NAME}"
			;;
			"#REPO_SUBDIR="*) REPO_SUBDIR="${myregex#\#REPO_SUBDIR=}" ; [ "${REPO_SUBDIR_PATCH}" = "${REPO_SUBDIR}" ] || run_patch=1;;
			"#GIT_REF="*) GIT_REF="${myregex#\#GIT_REF=}" ; [ "${REPO_SUBDIR_PATCH}" = "${REPO_SUBDIR}" ] || run_patch=1;;
			"#"*) : ;;
			[a-z]*) allregex="${allregex} ${myregex}" ;;
		esac

		if [ -z "${allregex}" ] ; then
			run_patch=0
		elif [ ${run_patch} -gt 0 ] ; then
			do_run_patch && run_patch=0 && allregex=""
		fi

	done < "${mykit}.kit"
	[ -n "${allregex}" ] && do_run_patch

done


