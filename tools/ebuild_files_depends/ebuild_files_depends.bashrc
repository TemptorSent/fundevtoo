function post_src_prepare()
{
	if [ -n "$_EMERGE_HOOK_FILES_DEPENDS" ] ; then
		perl ~portage/.emerge_hooks/ebuild_files_depends.pl | tee "${TEMP}/subbed.ebuild"
	fi
}
