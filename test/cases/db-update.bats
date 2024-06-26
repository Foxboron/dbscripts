load ../lib/common

@test "add simple packages" {
	local arches=('i686' 'x86_64')
	local pkgs=('pkg-simple-a' 'pkg-simple-b')
	local pkgbase
	local arch

	for pkgbase in ${pkgs[@]}; do
		releasePackage extra ${pkgbase}
	done

	db-update

	for pkgbase in ${pkgs[@]}; do
		checkPackage extra ${pkgbase} 1-1
	done
}

@test "add single simple package" {
	releasePackage extra 'pkg-single-arch'
	db-update
	checkPackage extra 'pkg-single-arch' 1-1
}

@test "add debug package" {
	releasePackage extra 'pkg-debuginfo'
	db-update
	checkPackage extra 'pkg-debuginfo' 1-1
	checkPackage extra-debug 'pkg-debuginfo' 1-1
}

@test "add single epoch package" {
	releasePackage extra 'pkg-single-epoch'
	db-update
	checkPackage extra 'pkg-single-epoch' 1:1-1
}

@test "add any packages" {
	local pkgs=('pkg-any-a' 'pkg-any-b')
	local pkgbase

	for pkgbase in ${pkgs[@]}; do
		releasePackage extra ${pkgbase}
	done

	db-update

	for pkgbase in ${pkgs[@]}; do
		checkPackage extra ${pkgbase} 1-1
	done
}

@test "add split packages" {
	local arches=('i686' 'x86_64')
	local pkgs=('pkg-split-a' 'pkg-split-b')
	local pkg
	local pkgbase
	local arch

	for pkgbase in ${pkgs[@]}; do
		releasePackage extra ${pkgbase}
	done

	db-update

	for pkgbase in ${pkgs[@]}; do
		checkPackage extra ${pkgbase} 1-1
	done
}

@test "update any package" {
	releasePackage extra pkg-any-a
	db-update

	updatePackage pkg-any-a

	releasePackage extra pkg-any-a
	db-update

	checkPackage extra pkg-any-a 1-2
}

@test "update any package to different repositories at once" {
	releasePackage extra pkg-any-a

	updatePackage pkg-any-a

	releasePackage testing pkg-any-a

	db-update

	checkPackage extra pkg-any-a 1-1
	checkPackage testing pkg-any-a 1-2
}

@test "archive package when releasing" {
	releasePackage extra pkg-any-a
	db-update
	[[ -f ${ARCHIVE_BASE}/packages/p/pkg-any-a/pkg-any-a-1-1-any${PKGEXT} ]]
	[[ -f ${ARCHIVE_BASE}/packages/p/pkg-any-a/pkg-any-a-1-1-any${PKGEXT}.sig ]]
}

@test "update any package to stable repo without updating testing package fails" {
	releasePackage extra pkg-any-a
	db-update
	updatePackage pkg-any-a
	releasePackage testing pkg-any-a
	db-update
	updatePackage pkg-any-a
	releasePackage extra pkg-any-a

	run ! db-update
}

@test "update any package to stable repo without updating staging package fails" {
	releasePackage extra pkg-any-a
	db-update
	updatePackage pkg-any-a
	releasePackage staging pkg-any-a
	db-update
	updatePackage pkg-any-a
	releasePackage extra pkg-any-a

	run ! db-update
}

@test "update same any package to same repository fails" {
	releasePackage extra pkg-any-a
	db-update
	checkPackage extra pkg-any-a 1-1

	PKGEXT=.pkg.tar.gz releasePackage extra pkg-any-a
	run ! db-update
}

@test "update duplicate package fails" {
	PKGEXT=.pkg.tar.xz releasePackage extra pkg-any-a
	PKGEXT=.pkg.tar.gz releasePackage extra pkg-any-a
	run ! db-update
}

@test "update same any package to different repositories fails" {
	local arch

	releasePackage extra pkg-any-a
	db-update
	checkPackage extra pkg-any-a 1-1

	releasePackage testing pkg-any-a
	run ! db-update

	checkRemovedPackageDB testing pkg-any-a
}

@test "add incomplete split package fails" {
	local arches=('i686' 'x86_64')
	local repo='extra'
	local pkgbase='pkg-split-a'
	local arch

	releasePackage ${repo} ${pkgbase}

	# remove a split package to make db-update fail
	rm "${STAGING}"/extra/${pkgbase}1-*

	run ! db-update

	checkRemovedPackageDB ${repo} ${pkgbase}
}

@test "add package to unknown repo fails" {
	mkdir "${STAGING}/unknown/"
	releasePackage extra 'pkg-any-a'
	releasePackage unknown 'pkg-any-b'
	run ! db-update
	run ! checkPackage extra 'pkg-any-a' 1-1
	[ ! -e "${FTP_BASE}/unknown" ]
	rm -rf "${STAGING}/unknown/"
}

@test "add unsigned package fails" {
	releasePackage extra 'pkg-any-a'
	rm "${STAGING}"/extra/*.sig
	run ! db-update

	checkRemovedPackageDB extra pkg-any-a
}

@test "add invalid signed package fails" {
	local p
	releasePackage extra 'pkg-any-a'
	for p in "${STAGING}"/extra/*${PKGEXT}; do
		printf '%s\n' "Not a real package" | gpg -v --detach-sign --no-armor --use-agent - > "${p}.sig"
	done
	run ! db-update

	checkRemovedPackageDB extra pkg-any-a
}

@test "add broken signature fails" {
	local s
	releasePackage extra 'pkg-any-a'
	for s in "${STAGING}"/extra/*.sig; do
		echo 0 > $s
	done
	run ! db-update

	checkRemovedPackageDB extra pkg-any-a
}

@test "add broken package fails" {
	local p
	releasePackage extra 'pkg-any-a'
	for p in "${STAGING}"/extra/*${PKGEXT}; do
		echo >> "${p}"
	done
	run ! db-update

	checkRemovedPackageDB extra pkg-any-a
}

@test "add package with inconsistent version fails" {
	local p
	releasePackage extra 'pkg-any-a'

	for p in "${STAGING}"/extra/*; do
		mv "${p}" "${p/pkg-any-a-1/pkg-any-a-2}"
	done

	run ! db-update
	checkRemovedPackageDB extra 'pkg-any-a'
}

@test "add package with inconsistent name fails" {
	local p
	releasePackage extra 'pkg-any-a'

	for p in "${STAGING}"/extra/*; do
		mv "${p}" "${p/pkg-/foo-pkg-}"
	done

	run ! db-update
	checkRemovedPackageDB extra 'pkg-any-a'
}

@test "add package with inconsistent pkgbuild in branch succeeds" {
	releasePackage extra 'pkg-any-a'

	updateRepoPKGBUILD 'pkg-any-a' extra any

	db-update
	checkPackage extra 'pkg-any-a' 1-1
}

@test "add package with inconsistent pkgbuild in tag fails" {
	releasePackage extra 'pkg-any-a'

	retagModifiedPKGBUILD 'pkg-any-a'

	run ! db-update
	checkRemovedPackageDB extra 'pkg-any-a'
}

@test "add package with insufficient directory permissions fails" {
	releasePackage core 'pkg-any-a'
	releasePackage extra 'pkg-any-b'

	chmod -xwr ${FTP_BASE}/core/os/i686
	run ! db-update
	chmod +xwr ${FTP_BASE}/core/os/i686

	checkRemovedPackageDB core 'pkg-any-a'
	checkRemovedPackageDB extra 'pkg-any-b'
}

@test "add package with insufficient repo permissions fails" {
	releasePackage noperm 'pkg-any-a'
	releasePackage extra 'pkg-any-b'

	run ! db-update

	checkRemovedPackageDB noperm 'pkg-any-a'
	checkRemovedPackageDB extra 'pkg-any-b'
}

@test "package has to be aregular file" {
	local p
	local target=$(mktemp -d)
	local arches=('i686' 'x86_64')

	releasePackage extra 'pkg-simple-a'

	for p in "${STAGING}"/extra/*i686*; do
		mv "${p}" "${target}"
		ln -s "${target}/${p##*/}" "${p}"
	done

	run ! db-update
	checkRemovedPackageDB extra "pkg-simple-a"
}

@test "Wrong BUILDDIR" {
	local target=$(mktemp -d)
	BUILDDIR=$target releasePackage extra 'pkg-single-arch'
	run ! db-update
	[[ $output == *'was not built in a chroot'* ]]
}

@test "Wrong BUILDTOOL" {
	BUILDTOOL=dbscripts releasePackage extra 'pkg-buildtool-single-arch'
	run ! db-update
	[[ $output == *'was not built with devtools'* ]]
}

@test "Wrong PACKAGER domain" {
	PACKAGER_OVERRIDE="Bob Tester <tester@wrong>" releasePackage extra 'pkg-packager-domain'
	run ! db-update
	[[ $output == *'does not have a valid packager'* ]]
}

@test "Wrong PACKAGER claim" {
	PACKAGER_OVERRIDE="Bob Tester <wrong@localhost>" releasePackage extra 'pkg-packager-claim'
	run ! db-update
	[[ $output == *'does not have a valid packager'* ]]
}

@test "override PACKAGER name label" {
	PACKAGER_OVERRIDE="Bot (the real) Tester <tester@localhost>" releasePackage extra 'pkg-packager-name'
	db-update
	checkPackage extra 'pkg-packager-name' 1-1
}

@test "add split debug packages" {
	local arches=('i686' 'x86_64')
	local pkgs=('pkg-split-debuginfo')
	local pkg
	local pkgbase
	local arch

	for pkgbase in ${pkgs[@]}; do
		releasePackage extra ${pkgbase}
	done

	db-update

	for pkgbase in ${pkgs[@]}; do
		checkPackage extra-debug ${pkgbase} 1-1
	done
}

@test "add package with author mapping" {
	releasePackage extra pkg-any-a

	db-update

	checkPackage extra pkg-any-a 1-1
	checkStateRepoAutoredBy "Bob Tester <tester@localhost>"
}

@test "add package with missing author mapping fails" {
	releasePackage extra pkg-any-a

	emptyAuthorsFile
	run ! db-update

	checkRemovedPackage extra pkg-any-a
}

@test "downgrade package fails" {
	releasePackage extra pkg-any-a
	for p in "${STAGING}"/extra/*${PKGEXT} "${STAGING}"/extra/*.sig; do
		mv "${p}" "${TMP}/"
	done

	updatePackage pkg-any-a
	releasePackage extra pkg-any-a
	db-update

	checkPackage extra pkg-any-a 1-2

	for p in "${TMP}"/*${PKGEXT} "${TMP}"/*.sig; do
		mv "${p}" "${STAGING}/extra/"
	done

	run ! db-update
	checkPackage extra pkg-any-a 1-2
}

@test "same pkgver in different staged repos fails" {
	releasePackage extra pkg-any-a
	releasePackage testing pkg-any-a

	run ! db-update
	run ! checkPackage extra pkg-any-a 1-1
	run ! checkPackage testing pkg-any-a 1-1
}

@test "staged testing newer than staged extra" {
	releasePackage extra pkg-any-a
	updatePackage pkg-any-a
	releasePackage testing pkg-any-a

	db-update
	checkPackage extra pkg-any-a 1-1
	checkPackage testing pkg-any-a 1-2
}

@test "staged staging newer than staged testing" {
	releasePackage testing pkg-any-a
	updatePackage pkg-any-a
	releasePackage staging pkg-any-a

	db-update
	checkPackage testing pkg-any-a 1-1
	checkPackage staging pkg-any-a 1-2
}

@test "staged extra newer than staged testing fails" {
	releasePackage testing pkg-any-a
	updatePackage pkg-any-a
	releasePackage extra pkg-any-a

	run ! db-update
	run ! checkPackage extra pkg-any-a 1-2
	run ! checkPackage testing pkg-any-a 1-1
}

@test "staged extra newer than staged staging fails" {
	releasePackage staging pkg-any-a
	updatePackage pkg-any-a
	releasePackage extra pkg-any-a

	run ! db-update
	run ! checkPackage extra pkg-any-a 1-2
	run ! checkPackage staging pkg-any-a 1-1
}

@test "staged testing newer than staged staging fails" {
	releasePackage staging pkg-any-a
	updatePackage pkg-any-a
	releasePackage testing pkg-any-a

	run ! db-update
	run ! checkPackage testing pkg-any-a 1-2
	run ! checkPackage staging pkg-any-a 1-1
}

@test "staged multiple times in same stability layer fails" {
	releasePackage extra pkg-any-a
	updatePackage pkg-any-a
	releasePackage core pkg-any-a

	run ! db-update
	run ! checkPackage extra pkg-any-a 1-1
	run ! checkPackage core pkg-any-a 1-2
}

@test "staged multiple times in same repo fails" {
	releasePackage extra pkg-any-a
	updatePackage pkg-any-a
	releasePackage extra pkg-any-a

	run ! db-update
	run ! checkPackage extra pkg-any-a 1-1
	run ! checkPackage extra pkg-any-a 1-2
}
