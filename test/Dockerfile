FROM docker.io/archlinux/archlinux

RUN pacman -Syu --noconfirm --needed \
		sudo \
		fakeroot \
		awk \
		subversion \
		make \
		kcov \
		bats \
		gettext \
		grep \
		tree \
		binutils \
		git \
		parallel \
		coreutils \
		sequoia-sq

RUN pacman-key --init && \
	echo '%wheel ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel && \
	echo '%packager ALL = (archive) NOPASSWD: /dbscripts/db-archive' > /etc/sudoers.d/dbscripts && \
	groupadd packager && \
	useradd -N -g users -G wheel,packager -d /build -m tester && \
	useradd -M archive && \
	ln -sf /dbscripts/db-archive /usr/local/bin/ && \
	ln -sf /dbscripts/db-move /usr/local/bin/ && \
	ln -sf /dbscripts/db-remove /usr/local/bin/ && \
	ln -sf /dbscripts/db-repo-add /usr/local/bin/ && \
	ln -sf /dbscripts/db-repo-remove /usr/local/bin/ && \
	ln -sf /dbscripts/db-update /usr/local/bin/ && \
	ln -sf /dbscripts/testing2x /usr/local/bin/ && \
	ln -sf /dbscripts/cron-jobs/devlist-mailer /usr/local/bin/ && \
	ln -sf /dbscripts/cron-jobs/ftpdir-cleanup /usr/local/bin/ && \
	ln -sf /dbscripts/cron-jobs/integrity-check /usr/local/bin/ && \
	ln -sf /dbscripts/cron-jobs/sourceballs /usr/local/bin/ && \
	mkdir -p /etc/dbscripts/ && \
	echo "tester <tester@archlinux.org> tester" > /etc/dbscripts/authors.conf && \
	echo 0 > /srv/ftp/lastupdate && \
	mkdir -p \
		/srv/archive \
		/srv/repos/state \
		/srv/ftp/pool/packages{,-debug} \
		/srv/ftp/{{core,extra,multilib}{,-testing,-staging},gnome-unstable}/os/x86_64/ && \
	chgrp packager \
		/srv/ftp/lastupdate \
		/srv/repos/state \
		/srv/ftp/pool/packages{,-debug} \
		/srv/ftp/{{core,extra,multilib}{,-testing,-staging},gnome-unstable}/os/x86_64/ && \
	chown archive:archive /srv/archive && \
	chmod 775 \
		/srv/ftp/lastupdate \
		/srv/repos/state \
		/srv/ftp/pool/packages{,-debug} \
		/srv/ftp/{{core,extra,multilib}{,-testing,-staging},gnome-unstable}/os/x86_64/ && \
	echo -e "[safe]\n\tdirectory = *\n" > /etc/gitconfig

USER tester

RUN sq key generate --userid "Bob Tester <tester@localhost>" --output /build/private.key && \
	sq export --keyring /build/private.key | sudo pacman-key -a - && \
	sudo pacman-key --lsign-key tester@localhost && \
	gpg --import /build/private.key && \
	gpgconf --kill gpg-agent && \
	gpgconf --kill keyboxd && \
	mkdir -p \
		/build/staging/{{core,extra,multilib}{,-testing,-staging},gnome-unstable} && \
	git config --global user.email "tester@localhost" && \
	git config --global user.name "Bob Tester" && \
	git -C /srv/repos/state init --initial-branch=main --shared=group .

ENV PACKAGER="Bob Tester <tester@localhost>"
