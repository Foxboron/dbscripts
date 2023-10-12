load ../lib/common

@test "commands display usage message by default" {
	for cmd in db-move db-repo-add db-repo-remove testing2x; do
		echo Testing $cmd
		run ! $cmd
		[[ $output == *'usage: '* ]]
	done
	for cmd in db-remove; do
		echo Testing $cmd
		run ! $cmd
		[[ $output == *'Usage: '* ]]

		echo Testing $cmd --help
		run -0 $cmd --help
		[[ $output == *'Usage: '* ]]
	done
}
