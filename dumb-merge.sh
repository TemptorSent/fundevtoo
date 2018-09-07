#!/bin/sh
# Simple-stupid extract and merge script.

# Setup basics
REPO_SRC_ROOT="../source-trees"
REPO_DEST_ROOT="../temptorsent-dest-trees"
REPO_DEST_PATCHES="${REPO_DEST_ROOT}/patchsets"

GENTOO_REPO="https://anongit.gentoo.org/git/repo/gentoo.git"
GENTOO_ROOT="${REPO_SRC_ROOT}/gentoo"
mkdir -p "${REPO_SRC_ROOT}"
mkdir -p "${REPO_DEST_PATCHES}"

if ! [ -d "${GENTOO_ROOT}" ] ; then
	pushd "${REPO_SRC_ROOT}"
		git clone "${GENTOO_REPO}" "${GENTOO_ROOT##*/}"
	popd
else
	: # echo "To update gentoo repo: cd ../source-trees/gentoo && git pull"
fi
REPO_NAME="gentoo"
REPO_ROOT="${GENTOO_ROOT}"

# Load list of kits to generate
while read -r mykit; do
	KITLIST="${KITLIST:+${KITLIST} }${mykit}"
done < kit.list

for mykit in ${KITLIST} ; do
	GITCOMMIT=""
	allregex=""
	while read -r myregex; do
		case "${myregex}" in
			"#REPO_NAME="*) REPO_NAME="${myregex#\#REPO_NAME=}" ;; # && (cd "${REPO_ROOT}" && git checkout ${GITCOMMIT} ) ;;
			"#GITCOMMIT="*) GITCOMMIT="${myregex#\#GITCOMMIT=}" ;; # && (cd "${REPO_ROOT}" && git checkout ${GITCOMMIT} ) ;;
			"#"*) : ;;
			[a-z]*) allregex="${allregex} ${myregex}" ;;
		esac
	done < "${mykit}.kit"
	(cd "${REPO_ROOT}" && git log --pretty=email --patch-with-stat --reverse --full-index --binary ${GITCOMMIT} -- ${allregex} ) > "${REPO_DEST_PATCHES}/${mykit}-${REPO_NAME}-${GITCOMMIT}.patch"
done


