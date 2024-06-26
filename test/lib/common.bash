. /usr/share/makepkg/util.sh
shopt -s extglob

bats_require_minimum_version 1.5.0

__updatePKGBUILD() {
	local pkgrel

	pkgrel=$(. PKGBUILD; expr ${pkgrel} + 1)
	sed "s/pkgrel=.*/pkgrel=${pkgrel}/" -i PKGBUILD
	git add .
	git commit -m "update pkg to pkgrel=${pkgrel}"
	git push
}

__retagModifiedPKGBUILD() {
	local pkgver
	local pkgrel
	local gittag

	pkgver=$(. PKGBUILD; echo "${pkgrel}")
	pkgrel=$(. PKGBUILD; echo "${pkgrel}")
	gittag="${pkgver}-${pkgrel}"

	echo >> PKGBUILD
	git add PKGBUILD
	git commit -m "modified PKGBUILD"

	# re-tag
	git push origin :"${gittag}"
	git tag -d "${gittag}"
	git tag -s -m "released ${gittag}"  "${gittag}"
	git push --tags origin main
}

__getCheckSum() {
	local result
	result="$(sha1sum "$1")"
	echo "${result%% *}"
}

# Converts from the git repository tag to the PKGBUILD tag
# Input     1-1.0.0-1
# Output    1:1.0.0-1
__parseGitTag(){
	tag="${1}"
	while IFS=- read -r pkgrel pkgver epoch; do
		test -n "${epoch}" && printf "%s:" "$epoch"
		printf "%s" "$(echo "$pkgver" | rev)"
		printf "%s" "$(echo "$pkgrel-" | rev)"
	done < <(echo "${tag}" | rev)
}

# Proxy function to check if a file exists. Using [[ -f ... ]] directly is not
# always wanted because we might want to expand bash globs first. This way we
# can pass unquoted globs to __isGlobfile() and have them expanded as function
# arguments before being checked.
#
# This is a copy of db-functions is_globfile
__isGlobfile() {
	[[ -f $1 ]]
}

##
#  usage : lock( $fd, $file )
##
lock() {
	# Only reopen the FD if it wasn't handed to us
	if ! [[ "/dev/fd/$1" -ef "$2" ]]; then
		mkdir -p -- "$(dirname -- "$2")"
		eval "exec $1>"'"$2"'
	fi

	if ! flock --wait 600 "$1"; then
		error "Failed to acquire lock on %s" "$2"
		exit 1
	fi
}

##
#  usage : unlock( $fd )
##
unlock() {
	local fd=$1
	# https://github.com/koalaman/shellcheck/issues/862
	# shellcheck disable=2034
	exec {fd}>&-
}

__buildPackage() {
	local pkgdest=${1:-.}
	local p
	local cache
	local pkgarches
	local tarch
	local pkgfiles

	if [[ -n ${BUILDDIR} ]]; then
		cache=${BUILDDIR}/$(__getCheckSum PKGBUILD)
		mkdir -p "${cache}"
		lock 9 "${cache}/.lock"

		if cp -Lv ${cache}/*${PKGEXT}{,.sig} ${pkgdest} 2>/dev/null; then
			unlock 9
			return 0
		fi
	fi

	if [[ -z ${BUILDTOOL} ]]; then
		BUILDTOOL=devtools
	fi

	pkgarches=($(. PKGBUILD; echo ${arch[@]}))
	for tarch in ${pkgarches[@]}; do
		if [ "${tarch}" == 'any' ]; then
			PKGDEST=${pkgdest} PKGEXT=${PKGEXT} BUILDTOOL=${BUILDTOOL} PACKAGER=${PACKAGER_OVERRIDE:-${PACKAGER}} makepkg -c
			mapfile -tO "${#pkgfiles[@]}" pkgfiles < <(PKGDEST=${pkgdest} PKGEXT=${PKGEXT} makepkg --packagelist)
		else
			PKGDEST=${pkgdest} PKGEXT=${PKGEXT} CARCH=${tarch} BUILDTOOL=${BUILDTOOL} PACKAGER=${PACKAGER_OVERRIDE:-${PACKAGER}} makepkg -c
			mapfile -tO "${#pkgfiles[@]}" pkgfiles < <(PKGDEST=${pkgdest} PKGEXT=${PKGEXT} CARCH=${tarch} makepkg --packagelist)
		fi
	done

	for p in ${pkgfiles[@]}; do
		sq sign --detached --binary --signer-file /build/private.key --output "${p}.sig" "${p}"

		if [[ -n ${BUILDDIR} ]]; then
			cp -Lv ${p}{,.sig} ${cache}/
		fi
	done
	unlock 9
}

__archrelease() {
	local repo=$1
	local pkgarches
	local tarch
	local tag
	local rev
	local head

	pkgver=$(. PKGBUILD; get_full_version)
	gittag=${pkgver/:/-}

	# avoid trying to tag the same commit twice
	if rev=$(git rev-list -n1 "$gittag" 2>/dev/null); then
		head=$(git rev-parse HEAD)
		if [[ "$rev" != "$head" ]]; then
			error "failed to tag revision %s" "${head}"
			error "tag '%s' already exists for revision %s" "${gittag}" "${rev}"
			exit 1
		fi
		return 0
	fi
	git tag -s -m "released $pkgbase-$pkgver"  "$gittag"
	git push --tags origin main
}

setup() {
	local p
	local pkg
	local r
	local a
	local username
	PKGEXT=".pkg.tar.xz"

	TMP="$(mktemp --directory --tmpdir 'tmp.dbscripts-tests-XXXXXXXXXXXX')"
	chmod 770 "$TMP"

	export DBSCRIPTS_CONFIG=${TMP}/config.local
	cat <<eot > "${DBSCRIPTS_CONFIG}"
	FTP_BASE="${TMP}/ftp"
	ARCHIVE_BASE="${TMP}/archive"
	ARCHIVEUSER=""
	PKGREPOS=('core' 'extra' 'testing' 'staging' 'unstable' 'noperm')
	DEBUGREPOS=('core-debug' 'extra-debug' 'testing-debug' 'staging-debug' 'unstable-debug')
	ACL=([users]="extra core staging testing unstable core-debug extra-debug testing-debug staging-debug unstable-debug")

	PKGPOOL='pool/packages'
	DEBUGPKGPOOL='pool/packages-debug'
	SRCPOOL='sources/packages'
	UNSTABLE_REPOS=(unstable)
	STAGING_REPOS=('staging')
	TESTING_REPOS=('testing')
	STABLE_REPOS=('core' 'extra' 'noperm')
	CLEANUP_DESTDIR="${TMP}/package-cleanup"
	SOURCE_CLEANUP_DESTDIR="${TMP}/source-cleanup"
	STAGING="${TMP}/staging"
	TMPDIR="${TMP}/tmp"
	ARCHES=(x86_64 i686)
	CLEANUP_DRYRUN=false
	SOURCE_CLEANUP_DRYRUN=false
	KEYRING="/etc/pacman.d/gnupg"
	GIT_PACKAGING_REPOS_URL="${TMP}/git-packages"
	GIT_STATE_REPO="${TMP}/repository"
	GIT_PACKAGES_CACHE="${TMP}/git-pkg-repos"
	LOCK_DIR="${TMP}/lock"
	AUTHORS="${TMP}/authors.conf"
	PACKAGER_DOMAIN=localhost

	if [[ -f "${TMP}/config.override" ]]; then
		. "${TMP}/config.override"
	fi
eot

	username=$(/usr/bin/id -un)
	cat <<eot > "${TMP}/authors.conf"
qux <a@b.local> dux
Bob Tester <tester@localhost> ${username}
muh <muh@cow> cow
${username} <${username}@yay> doo
eot

	. config

	# This is for our git clones when initializing bare repos
	TMP_WORKDIR_GIT=${TMP}/git-clones

	mkdir -p "${TMP}/"{ftp,tmp,staging,{package,source}-cleanup}
	mkdir -p "${GIT_PACKAGING_REPOS_URL}"
	mkdir -p "${TMP_WORKDIR_GIT}"

	for r in ${PKGREPOS[@]}; do
		mkdir -p "${TMP}"/staging/${r}{,-debug}
		for a in ${ARCHES[@]}; do
			mkdir -p "${TMP}"/ftp/${r}{,-debug}/os/${a}
		done
	done
	mkdir -p "${TMP}/ftp/${PKGPOOL}"
	mkdir -p "${TMP}/ftp/${SRCPOOL}"
	mkdir -p "${TMP}/ftp/${DEBUGPKGPOOL}"

	# make dummy packages for "reproducibility"
	pacman -Qi | awk -F': ' '\
        /^Name .*/ {printf "%s", $2} \
        /^Version .*/ {printf "-%s", $2} \
        /^Architecture .*/ {print "-"$2} \
        ' | while read -r line; do
			line=$line.pkg.tar.xz
			pkgname=${line%-*-*-*}
			mkdir -p "${ARCHIVE_BASE}/packages/${pkgname:0:1}/${pkgname}"
			touch "${ARCHIVE_BASE}/packages/${pkgname:0:1}/${pkgname}/${line}"{,.sig}
		done

	git init --bare --shared=group "${TMPDIR}/git-packages-bare.git"
	mkdir "${GIT_STATE_REPO}"
	chmod 777 "${GIT_STATE_REPO}"
	git -c "core.sharedRepository=group" clone "${TMPDIR}/git-packages-bare.git" "${GIT_STATE_REPO}" 2>/dev/null
}

teardown() {
	rm -rf "${TMP}"
}

enablePermission() {
	local repo=$1
	grep ACL "${TMP}/config.local" | sed 's/")/ '"$repo"'")/' > "${TMP}/config.override"
}

disablePermissionOverride() {
	rm -f "${TMP}/config.override"
}

releasePackage() {
	local repo=$1
	local pkgbase=$2

	if [ ! -d "${GIT_PACKAGING_REPOS_URL}/${pkgbase}.git" ]; then
		git init --bare --shared=all "${GIT_PACKAGING_REPOS_URL}/${pkgbase}".git
		git -c "core.sharedRepository=group" clone "${GIT_PACKAGING_REPOS_URL}/${pkgbase}".git "${TMP_WORKDIR_GIT}/${pkgbase}"
		cp -r "fixtures/${pkgbase}"/* "${TMP_WORKDIR_GIT}/${pkgbase}"
		git -C "${TMP_WORKDIR_GIT}/${pkgbase}" add "${TMP_WORKDIR_GIT}/${pkgbase}"/*
		git -C "${TMP_WORKDIR_GIT}/${pkgbase}" commit -m "initial commit of ${pkgbase}"
		git -C "${TMP_WORKDIR_GIT}/${pkgbase}" push

	fi

	if [ ! -d "${TMP_WORKDIR_GIT}/${pkgbase}" ]; then
		git clone --origin origin "${GIT_PACKAGING_REPOS_URL}/${pkgbase}.git" "${TMP_WORKDIR_GIT}/${pkgbase}"
	fi

	pushd "${TMP_WORKDIR_GIT}/${pkgbase}"
	git pull origin main
	__buildPackage "${STAGING}"/${repo}
	__archrelease ${repo}
	chmod -R 777 "${GIT_PACKAGING_REPOS_URL}/"
	popd
}

emptyAuthorsFile() {
	echo > "${TMP}/authors.conf"
}

updatePackage() {
	local pkgbase=$1

	pushd "${TMP_WORKDIR_GIT}/${pkgbase}"
	git pull origin main
	__updatePKGBUILD
	__buildPackage
	popd
}

updateRepoPKGBUILD() {
	local pkgbase=$1
	local repo=$2
	local arch=$3

	pushd "${TMP_WORKDIR_GIT}/${pkgbase}"
	__updatePKGBUILD
	popd
}

retagModifiedPKGBUILD() {
	local pkgbase=$1

	pushd "${TMP_WORKDIR_GIT}/${pkgbase}"
	__retagModifiedPKGBUILD
	popd
}

checkPackageDB() {
	local repo=$1
	local pkgbase=$2
	local pkgver=$3
	local db
	local pkgarch
	local repoarch
	local repoarches
	local pkgfile
	local pkgname

	local pkgarches=($(. "fixtures/$pkgbase/PKGBUILD"; echo ${arch[@]}))
	# TODO: We need a better way to figure out when we are dealing with
	#       debug packages
	if [[ "${repo}" = *-debug ]]; then
		local pkgnames=("${pkgbase}-debug")
	else
		local pkgnames=($(. "fixtures/$pkgbase/PKGBUILD";  echo "${pkgname[@]}"))
	fi

	if [[ ${pkgarches[@]} == any ]]; then
		repoarches=(${ARCHES[@]})
	else
		repoarches=(${pkgarches[@]})
	fi

	for pkgarch in ${pkgarches[@]}; do
		for pkgname in ${pkgnames[@]}; do
			pkgfile="${pkgname}-${pkgver}-${pkgarch}${PKGEXT}"
			[ -r ${FTP_BASE}/${PKGPOOL}/${pkgfile} ] || [ -r ${FTP_BASE}/${DEBUGPKGPOOL}/${pkgfile} ]
			[ -r ${FTP_BASE}/${PKGPOOL}/${pkgfile}.sig ] || [ -r ${FTP_BASE}/${DEBUGPKGPOOL}/${pkgfile}.sig ]
			[ ! -r ${STAGING}/${repo}/${pkgfile} ]
			[ ! -r ${STAGING}/${repo}/${pkgfile}.sig ]

			for repoarch in ${repoarches[@]}; do
				# Only 'any' packages can be found in repos of both arches
				if [[ $pkgarch != any ]]; then
					if [[ $pkgarch != ${repoarch} ]]; then
						continue
					fi
				fi

				[ -L ${FTP_BASE}/${repo}/os/${repoarch}/${pkgfile} ]
				[ "$(readlink -e ${FTP_BASE}/${repo}/os/${repoarch}/${pkgfile})" == ${FTP_BASE}/${PKGPOOL}/${pkgfile} ] || \
					[ "$(readlink -e ${FTP_BASE}/${repo}/os/${repoarch}/${pkgfile})" == ${FTP_BASE}/${DEBUGPKGPOOL}/${pkgfile} ]

				[ -L ${FTP_BASE}/${repo}/os/${repoarch}/${pkgfile}.sig ]
				[ "$(readlink -e ${FTP_BASE}/${repo}/os/${repoarch}/${pkgfile}.sig)" == ${FTP_BASE}/${PKGPOOL}/${pkgfile}.sig ] || \
					[ "$(readlink -e ${FTP_BASE}/${repo}/os/${repoarch}/${pkgfile}.sig)" == ${FTP_BASE}/${DEBUGPKGPOOL}/${pkgfile}.sig ]

				for db in ${DBEXT} ${FILESEXT}; do
					[ -r "${FTP_BASE}/${repo}/os/${repoarch}/${repo}${db%.tar.*}" ]
					bsdtar -xf "${FTP_BASE}/${repo}/os/${repoarch}/${repo}${db%.tar.*}" -O | grep -qFx "${pkgfile}"
				done
			done
		done
	done
}

checkPackage() {
	local repo=$1
	local pkgbase=$2
	local pkgver=$3

	local dirarches=() pkgbuildarches=()
	local pkgbuild dirarch pkgbuildver
	for pkgbuild in "${GIT_STATE_REPO}/${repo%-debug}-"+([^-])"/${pkgbase}"; do
		[[ -e $pkgbuild ]] || continue
		dirarch=${pkgbuild%/${pkgbase}}
		dirarch=${dirarch##*-}

		dirarches+=("$dirarch")
		pkgbuildarches+=($(. "${TMP_WORKDIR_GIT}/${pkgbase}/PKGBUILD"; echo ${arch[@]}))

		while read -r _ tag _; do
			pkgbuildver=$(__parseGitTag "$tag")
			[[ $pkgver = "$pkgbuildver" ]]
		done < "$pkgbuild"
	done
	# Verify that the arches-from-dirnames and
	# arches-from-PKGBUILDs agree (that a PKGBUILD existed for
	# every arch).
	(( ${#dirarches[@]} > 0 ))
	mapfile -d '' dirarches      < <(printf '%s\0' "${dirarches[@]}"      | sort -uz)
	mapfile -d '' pkgbuildarches < <(printf '%s\0' "${pkgbuildarches[@]}" | sort -uz)
	declare -p dirarches pkgbuildarches
	[[ "${dirarches[*]}" = "${pkgbuildarches[*]}" ]]

	checkPackageDB "$repo" "$pkgbase" "$pkgver"
}

checkRemovedPackage() {
	local repo=$1
	local pkgbase=$2

	if __isGlobfile "${GIT_STATE_REPO}/${repo%-debug}-"+([^-])"/${pkgbase}"; then
		return 1
	fi

	checkRemovedPackageDB $repo $pkgbase
}

checkRemovedPackageDB() {
	local repo=$1
	local pkgbase=$2
	local arch
	local db
	local tarch
	local tarches
	local pkgarches
	local pkgnames
	local pkgname

	pkgarches=($(. "fixtures/$pkgbase/PKGBUILD"; echo ${arch[@]}))

	# TODO: We need a better way to figure out when we are dealing with
	#       debug packages
	if [[ "${repo}" = *-debug ]]; then
		pkgnames=("${pkgbase}-debug")
	else
		pkgnames=($(. "fixtures/$pkgbase/PKGBUILD";  echo "${pkgname[@]}"))
	fi

	if [[ ${pkgarches[@]} == any ]]; then
		tarches=(${ARCHES[@]})
	else
		tarches=(${pkgarches[@]})
	fi

	for db in ${DBEXT} ${FILESEXT}; do
		for tarch in ${tarches[@]}; do
			if [ -r "${FTP_BASE}/${repo}/os/${tarch}/${repo}${db%.tar.*}" ]; then
				for pkgname in ${pkgnames[@]}; do
					if bsdtar -xf "${FTP_BASE}/${repo}/os/${tarch}/${repo}${db%.tar.*}" -O | grep ${pkgname} &>/dev/null; then
						return 1
					fi
				done
			fi
		done
	done
}

checkStateRepoAutoredBy() {
	local expected=$1
	local author

	if ! author=$(git -C "${GIT_STATE_REPO}" show -s --format='%an <%ae>' HEAD); then
		die 'Failed to query author of state repository'
	fi
	if [[ "${expected}" != "${author}" ]]; then
		error "Author doesn't match, expected: '%s', actual: '%s'" "${expected}" "${author}"
		return 1
	fi
	return 0
}

checkStateRepoContains() {
	local repo=$1
	local arch=$2
	local pkgbase=$3
	local state_file="${repo}-${arch}/${pkgbase}"

	if [[ ! -f "${GIT_STATE_REPO}/${state_file}" ]]; then
		return 1
	fi
	return 0
}
