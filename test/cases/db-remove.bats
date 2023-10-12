load ../lib/common

@test "remove single packages" {
	local arches=('i686' 'x86_64')
	local pkgs=('pkg-simple-a' 'pkg-simple-b' 'pkg-split-a' 'pkg-split-b' 'pkg-simple-epoch')
	local pkgbase
	local arch

	for pkgbase in ${pkgs[@]}; do
		releasePackage extra ${pkgbase}
	done

	db-update

	for pkgbase in ${pkgs[@]}; do
		for arch in ${arches[@]}; do
			db-remove --arch ${arch} extra ${pkgbase}
			run ! checkStateRepoContains extra ${arch} ${pkgbase}
		done
	done

	for pkgbase in ${pkgs[@]}; do
		checkRemovedPackage extra ${pkgbase}
	done
}

@test "remove debug package" {
	local arches=('i686' 'x86_64')
	local pkgs=('pkg-simple-a' 'pkg-simple-b' 'pkg-split-a' 'pkg-split-b' 'pkg-simple-epoch' 'pkg-debuginfo' 'pkg-split-debuginfo')
	local debug_pkgs=('pkg-debuginfo' 'pkg-split-debuginfo')
	local pkgbase
	local arch

	for pkgbase in ${pkgs[@]}; do
		releasePackage extra ${pkgbase}
	done

	db-update

	for pkgbase in ${pkgs[@]}; do
		for arch in ${arches[@]}; do
			db-remove --arch ${arch} extra ${pkgbase}
			run ! checkStateRepoContains extra ${arch} ${pkgbase}
		done
	done

    checkRemovedPackage extra pkg-debuginfo
	for pkgbase in ${debug_pkgs[@]}; do
		checkRemovedPackage extra-debug ${pkgbase}
	done
}

@test "remove specific debug package" {
	skip "removing only debug packages is currently unsupported"

	local arches=('i686' 'x86_64')
	local pkgs=('pkg-split-debuginfo')
	local debug_pkgs=('pkg-split-debuginfo')
	local pkgbase
	local arch

	for pkgbase in ${pkgs[@]}; do
		releasePackage extra ${pkgbase}
	done

	db-update

    # We might want to remove the specific debug package
    # without removing the repo packages
	for pkgbase in ${debug_pkgs[@]}; do
		for arch in ${arches[@]}; do
			db-remove --arch ${arch} extra-debug ${pkgbase}-debug
			checkStateRepoContains extra ${arch} ${pkgbase}
		done
	done

	for pkgbase in ${debug_pkgs[@]}; do
		checkRemovedPackageDB extra-debug ${pkgbase}
	done
}

@test "remove multiple packages" {
	local arches=('i686' 'x86_64')
	local pkgs=('pkg-simple-a' 'pkg-simple-b' 'pkg-split-a' 'pkg-split-b' 'pkg-simple-epoch')
	local pkgbase
	local arch

	for pkgbase in ${pkgs[@]}; do
		releasePackage extra ${pkgbase}
	done

	db-update

	for arch in ${arches[@]}; do
		db-remove --arch ${arch} extra ${pkgs[@]}
	done

	for pkgbase in ${pkgs[@]}; do
		checkRemovedPackage extra ${pkgbase}
		for arch in ${arches[@]}; do
			run ! checkStateRepoContains extra ${arch} ${pkgbase}
		done
	done
}

@test "remove partial split package" {
	local arches=('i686' 'x86_64')
	local arch db

	releasePackage extra pkg-split-a
	db-update

	for arch in ${arches[@]}; do
		db-remove --arch "${arch}" --partial extra pkg-split-a1
		checkStateRepoContains extra ${arch} pkg-split-a

		for db in db files; do
			if bsdtar -xf "$FTP_BASE/extra/os/${arch}/extra.${db}" -O | grep pkg-split-a1; then
				return 1
			fi
			bsdtar -xf "$FTP_BASE/extra/os/${arch}/extra.${db}" -O | grep pkg-split-a2
		done
	done
}

@test "remove any packages" {
	local pkgs=('pkg-any-a' 'pkg-any-b')
	local pkgbase

	for pkgbase in ${pkgs[@]}; do
		releasePackage extra ${pkgbase}
	done

	db-update

	for pkgbase in ${pkgs[@]}; do
		run -0 db-remove extra ${pkgbase}
	done

	for pkgbase in ${pkgs[@]}; do
		checkRemovedPackage extra ${pkgbase}
		run ! checkStateRepoContains extra any ${pkgbase}
	done
}

@test "remove package with insufficient repo permissions fails" {
	local pkgbase='pkg-any-a'

	releasePackage noperm ${pkgbase}

	enablePermission noperm
	db-update
	disablePermissionOverride

	run ! db-remove noperm ${pkgbase}

	checkPackage noperm ${pkgbase} 1-1
}

@test "remove package with author mapping" {
	releasePackage testing pkg-any-a
	db-update

	db-remove testing pkg-any-a

	checkRemovedPackage testing pkg-any-a
	checkStateRepoAutoredBy "Bob Tester <tester@localhost>"
}

@test "remove package with missing author mapping fails" {
	releasePackage testing pkg-any-a
	db-update

	emptyAuthorsFile
	run ! db-remove testing pkg-any-a

	checkPackage testing pkg-any-a 1-1
}

@test "remove native packages via any arch" {
	local pkgbase=pkg-simple-a
	local arches=('i686' 'x86_64')
	local arch

	releasePackage extra ${pkgbase}

	db-update
	db-remove extra ${pkgbase}

	checkRemovedPackage extra ${pkgbase}
	for arch in ${arches[@]}; do
		run ! checkStateRepoContains extra ${arch} ${pkgbase}
	done
}

@test "remove duplicate packages in command" {
	local pkgbase=pkg-simple-a
	local arches=('i686' 'x86_64')
	local arch

	releasePackage extra ${pkgbase}

	db-update
	db-remove extra ${pkgbase} ${pkgbase}

	checkRemovedPackage extra ${pkgbase}
	for arch in ${arches[@]}; do
		run ! checkStateRepoContains extra ${arch} ${pkgbase}
	done
}

@test "remove none existing pkgbase fails" {
	releasePackage extra pkg-any-a
	db-update

	run ! db-remove extra pkg-any-a zdoesnotexist
	[[ $output == *"Couldn't find package zdoesnotexist"* ]]

	checkPackage extra pkg-any-a 1-1
}
