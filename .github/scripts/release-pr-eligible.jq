def version: capture("^(?<major>0|[1-9][0-9]*)\\.(?<minor>0|[1-9][0-9]*)\\.(?<patch>0|[1-9][0-9]*)$") | [.major, .minor, .patch] | map(tonumber);
($current | version) as $baseline |
(.title | capture("^chore\\(main\\): release (?<version>[0-9]+\\.[0-9]+\\.[0-9]+)$").version | version) as $next |
.author.login == "app/kong-volcano-app" and
.baseRefName == "main" and
.headRefName == ("release-please--branches--main--components--" + $component) and
.isCrossRepository == false and
.isDraft == false and
($next > $baseline)
