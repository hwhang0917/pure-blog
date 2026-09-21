#!/usr/bin/env bash
# Syncs the site with content/*.md: renders new or changed posts through
# scripts/post.template.html, removes pages of posts set to published: false,
# regenerates index.html, feed.xml and sitemap.xml, and commits each change
# after asking. Windows users: run scripts/publish.ps1 instead.
#
# A post is a Markdown file with a front matter block:
#
#   ---
#   title: Post title
#   date: 2026-09-21
#   slug: post-title
#   description: One or two sentences for search results and the feed.
#   ---
#
# published defaults to true and is added if missing; published: false marks a
# draft and removes its page. Each page records a SHA1 of the Markdown, blog.conf
# and the post template, so editing any of them re-renders the post.
# Body headings start at ## (the h1 is the title). Image sources may be URLs,
# absolute paths, or paths relative to content/; they are copied into
# assets/posts/<slug>/ as 01.ext, 02.ext, ... and the Markdown is rewritten.
# Needs bash 3.2+, git, curl, and node (Markdown is converted with marked via npx).
set -euo pipefail
# bash 5.2+ expands & in ${var//pat/rep} to the match; our replacements contain &amp; etc.
shopt -u patsub_replacement 2>/dev/null || true

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MARKED="npx -y marked@18.0.13"
cd "$ROOT"

html_esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }
# fm FILE KEY: value of KEY in FILE's front matter (empty if missing)
fm() { awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1' "$1" | sed -n "s/^$2: *//p" | head -1; }
# page_hash SLUG: SHA1 recorded in the rendered page (empty if none)
page_hash() { sed -n 's/.*<!-- source sha1: \([0-9a-f]*\) -->.*/\1/p' "posts/$1/index.html" 2>/dev/null; }
# source_hash FILE: SHA1 of the Markdown plus everything else that shapes its page
source_hash() { cat blog.conf scripts/post.template.html "$1" | git hash-object --stdin --no-filters; }

# --- site config (blog.conf: KEY=value) ------------------------------------
# Values are HTML-escaped once here; they only ever land in HTML and XML.
for k in SITE_URL SITE_TITLE SITE_DESCRIPTION SITE_LANG AUTHOR_NAME AUTHOR_URL TIMEZONE; do
    v=$(sed -n "s/^$k=//p" blog.conf | head -1 | html_esc)
    [ -n "$v" ] || { echo "blog.conf needs $k" >&2; exit 1; }
    printf -v "$k" '%s' "$v"
done

# --- templates ---------------------------------------------------------------
# indent_html PAD: indent marked's flat output by PAD, one level deeper per
# list/blockquote; lines inside <pre> are left as they are
indent_html() {
    awk -v pad="$1" '
        inpre { print; if (/<\/pre>/) inpre = 0; next }
        {
            o = gsub(/<(ul|ol|blockquote)>/, "&"); c = gsub(/<\/(ul|ol|blockquote)>/, "&")
            if ($0 ~ /^<\//) depth -= c
            ind = pad; for (i = 0; i < depth; i++) ind = ind "    "
            print ($0 == "" ? "" : ind $0)
            if ($0 ~ /^<\//) depth += o; else depth += o - c
            if (/^<pre/ && !/<\/pre>/) inpre = 1
        }'
}
# render TEMPLATE: replaces every {{KEY}} with the variable of the same name.
# A placeholder alone on a line takes a multi-line value, indented like the line.
VARS="TITLE DESCRIPTION DATE SLUG SHA1 SITE_URL SITE_TITLE SITE_DESCRIPTION SITE_LANG AUTHOR_NAME AUTHOR_URL POSTS BODY"
TITLE= DESCRIPTION= DATE= SLUG= SHA1= POSTS= BODY=
block_re='^([[:space:]]*)\{\{([A-Z_]+)\}\}$'
render() {
    local line k
    while IFS= read -r line; do
        if [[ $line =~ $block_re ]]; then
            k=${BASH_REMATCH[2]}
            [ -z "${!k}" ] || indent_html "${BASH_REMATCH[1]}" <<< "${!k}"
            continue
        fi
        for k in $VARS; do line=${line//"{{$k}}"/${!k}}; done
        printf '%s\n' "$line"
    done < "$1"
}

# --- index.html, sitemap.xml, feed.xml -------------------------------------
rebuild_indexes() {
    local rows md date slug title desc latest
    # One line per rendered post: date, slug, title, description (tab separated), newest first.
    rows=$(for md in content/*.md; do
        slug=$(fm "$md" slug)
        [ -e "posts/$slug/index.html" ] || continue
        printf '%s\t%s\t%s\t%s\n' "$(fm "$md" date)" "$slug" \
            "$(fm "$md" title | html_esc)" "$(fm "$md" description | html_esc)"
    done | LC_ALL=C sort -r)
    latest=$(head -1 <<< "$rows" | cut -f1)

    POSTS=$(while IFS=$'\t' read -r date slug title _; do
        [ -n "$slug" ] || continue
        printf '<li><time datetime="%s">%s</time> <a href="posts/%s/">%s</a></li>\n' "$date" "$date" "$slug" "$title"
    done <<< "$rows")
    render scripts/index.template.html > index.html

    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
        echo "    <url>"
        echo "        <loc>$SITE_URL/</loc>"
        [ -z "$latest" ] || echo "        <lastmod>$latest</lastmod>"
        echo "    </url>"
        while IFS=$'\t' read -r date slug _; do
            [ -n "$slug" ] || continue
            echo "    <url>"
            echo "        <loc>$SITE_URL/posts/$slug/</loc>"
            echo "        <lastmod>$date</lastmod>"
            echo "    </url>"
        done <<< "$rows"
        echo '</urlset>'
    } > sitemap.xml

    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo "<feed xmlns=\"http://www.w3.org/2005/Atom\" xml:lang=\"$SITE_LANG\">"
        echo "    <title>$SITE_TITLE</title>"
        echo "    <subtitle>$SITE_DESCRIPTION</subtitle>"
        echo "    <link rel=\"alternate\" type=\"text/html\" href=\"$SITE_URL/\"/>"
        echo "    <link rel=\"self\" type=\"application/atom+xml\" href=\"$SITE_URL/feed.xml\"/>"
        echo "    <id>$SITE_URL/</id>"
        echo "    <updated>${latest:-1970-01-01}T00:00:00$TIMEZONE</updated>"
        echo '    <author>'
        echo "        <name>$AUTHOR_NAME</name>"
        echo "        <uri>$AUTHOR_URL</uri>"
        echo '    </author>'
        while IFS=$'\t' read -r date slug title desc; do
            [ -n "$slug" ] || continue
            echo '    <entry>'
            echo "        <title>$title</title>"
            echo "        <link rel=\"alternate\" type=\"text/html\" href=\"$SITE_URL/posts/$slug/\"/>"
            echo "        <id>$SITE_URL/posts/$slug/</id>"
            echo "        <published>${date}T00:00:00$TIMEZONE</published>"
            echo "        <updated>${date}T00:00:00$TIMEZONE</updated>"
            echo "        <summary>$desc</summary>"
            echo '    </entry>'
        done <<< "$rows"
        echo '</feed>'
    } > feed.xml
}

# --- one post --------------------------------------------------------------
publish() {
    local md=$1 title dir src n ext dest text out action
    title=$(fm "$md" title); DATE=$(fm "$md" date); SLUG=$(fm "$md" slug)
    TITLE=$(html_esc <<< "$title"); DESCRIPTION=$(fm "$md" description | html_esc)
    for v in TITLE DATE SLUG DESCRIPTION; do [ -n "${!v}" ] || { echo "$md: front matter needs $v" >&2; exit 1; }; done
    [[ $SLUG =~ ^[a-z0-9-]+$ ]] || { echo "$md: slug must be lowercase a-z, 0-9, hyphens: $SLUG" >&2; exit 1; }
    [[ $DATE =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "$md: date must be YYYY-MM-DD: $DATE" >&2; exit 1; }
    out="posts/$SLUG/index.html"
    action=publish; [ -e "$out" ] && action=edit
    echo "$action $SLUG"

    # Images: every ![alt](src) not already under assets/posts/<slug>/ is fetched
    # into the next free number there and the Markdown is rewritten to use it.
    # Fenced code blocks and inline code are skipped when looking for them.
    dir="assets/posts/$SLUG"
    while src=$(awk '/^```/{f=!f; next} !f' "$md" | sed 's/`[^`]*`//g' | grep -o '!\[[^]]*]([^)]*)' | sed 's/^!\[[^]]*](\([^) ]*\).*/\1/' | grep -v "^\.\./$dir/" | head -1); [ -n "$src" ]; do
        mkdir -p "$dir"
        n=$(ls "$dir" | sed -n 's/^\([0-9][0-9]*\).*/\1/p' | sort -n | tail -1)
        n=$((10#${n:-0} + 1))
        ext=${src%%[?#]*}; ext=${ext##*/}
        case $ext in *.*) ext=.${ext##*.} ;; *) ext= ;; esac
        dest=$(printf '%s/%02d%s' "$dir" "$n" "$ext")
        case $src in
            http://*|https://*) curl -fsSL -o "$dest" "$src" ;;
            /*) cp "$src" "$dest" ;;
            *) cp "content/$src" "$dest" ;;
        esac
        echo "  $src -> $dest"
        text=$(cat "$md")
        printf '%s\n' "${text//"]($src"/"](../$dest"}" > "$md"
    done

    [ -n "$(fm "$md" published)" ] || { awk 'NR>1 && $0=="---" && !d {print "published: true"; d=1} {print}' "$md" > "$md.tmp" && mv "$md.tmp" "$md"; }
    SHA1=$(source_hash "$md")

    # Render: body is everything after the front matter; ../assets/ becomes
    # ../../assets/ because the page lives one level deeper than content/.
    BODY=$(awk 'f{print} NR>1 && $0=="---" && !f{f=1}' "$md" | $MARKED | sed 's|="\.\./assets/|="../../assets/|g')
    mkdir -p "posts/$SLUG"
    render scripts/post.template.html > "$out"

    rebuild_indexes
    git add "$md" "posts/$SLUG" index.html sitemap.xml feed.xml
    [ -d "$dir" ] && git add "$dir"
    if [ $action = publish ]; then commit_or_exit "feat(blog): publish $title" "auto publish via script"
    else commit_or_exit "fix(blog): edit $title" "auto edit via script"; fi
}

unpublish() {
    local md=$1 title slug
    title=$(fm "$md" title); slug=$(fm "$md" slug)
    echo "delete $slug"
    git rm -rq "posts/$slug"
    rebuild_indexes
    git add "$md" index.html sitemap.xml feed.xml
    commit_or_exit "chore(blog): delete $title" "auto delete via script"
}

# commit_or_exit SUBJECT BODY: show what is staged, ask, commit or stop
commit_or_exit() {
    local answer
    git status --short
    read -r -p "Commit \"$1\"? [y/N] " answer
    [[ $answer == [yY] ]] || { echo "left staged, not committed"; exit 1; }
    git commit -q -m "$1" -m "$2"
    echo "  committed: $1"
}

count=0
for md in content/*.md; do
    slug=$(fm "$md" slug)
    if [ "$(fm "$md" published)" = false ]; then
        [ -e "posts/$slug/index.html" ] || continue
        unpublish "$md"
    else
        [ "$(source_hash "$md")" != "$(page_hash "$slug")" ] || continue
        publish "$md"
    fi
    count=$((count + 1))
done

# blog.conf or index.template.html may have changed without any post changing
rebuild_indexes
git add index.html sitemap.xml feed.xml
if ! git diff --cached --quiet -- index.html sitemap.xml feed.xml; then
    commit_or_exit "chore(blog): rebuild index" "auto rebuild via script"
    count=$((count + 1))
fi
echo "$count change(s)"
