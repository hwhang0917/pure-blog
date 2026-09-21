#Requires -Version 5.1
# Windows twin of scripts/publish.sh; see that file for the front matter format.
# Syncs the site with content/*.md: renders new or changed posts through
# scripts/post.template.html, removes pages of posts set to published: false,
# regenerates index.html, feed.xml and sitemap.xml, and commits each change
# after asking. Needs git and node (Markdown is converted with marked via npx).
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Root = Split-Path -Parent $PSScriptRoot
$Marked = 'marked@18.0.13'
Set-Location $Root
# .NET file APIs resolve relative paths against the process directory, not PowerShell's
[Environment]::CurrentDirectory = $Root

function Read-Text($path) { [IO.File]::ReadAllText($path) -replace "`r`n", "`n" }
function Write-Text($path, $text) { [IO.File]::WriteAllText($path, $text) }   # UTF-8, no BOM
function Html-Esc($s) { "$s".Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;') }
function Run { $rest = @($args | Select-Object -Skip 1); & $args[0] @rest; if ($LASTEXITCODE) { throw "$args failed ($LASTEXITCODE)" } }

# Front matter as a hashtable plus the Markdown body after it
function Read-Post($md) {
    $lines = (Read-Text $md).Split("`n")
    $end = [Array]::IndexOf($lines, '---', 1)
    if ($lines[0] -ne '---' -or $end -lt 0) { throw "${md}: missing front matter" }
    $meta = @{}
    foreach ($l in $lines[1..($end - 1)]) { if ($l -match '^([^:]+): *(.*)$') { $meta[$matches[1]] = $matches[2] } }
    @{ Meta = $meta; Body = $lines[($end + 1)..($lines.Length - 1)] -join "`n" }
}

# SHA1 recorded in the rendered page (empty if none)
function Get-PageHash($slug) {
    $page = "posts/$slug/index.html"
    if ((Test-Path $page) -and ((Read-Text $page) -match '<!-- source sha1: ([0-9a-f]+) -->')) { $matches[1] }
}
# SHA1 of the Markdown plus everything else that shapes its page
function Get-SourceHash($md) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) 'publish-source'
    Write-Text $tmp ((Read-Text blog.conf) + (Read-Text scripts/post.template.html) + (Read-Text $md))
    git hash-object --no-filters $tmp
}

# --- site config (blog.conf: KEY=value) ------------------------------------
# Values are HTML-escaped once here; they only ever land in HTML and XML.
$V = [ordered]@{}
foreach ($k in 'SITE_URL', 'SITE_TITLE', 'SITE_DESCRIPTION', 'SITE_LANG', 'AUTHOR_NAME', 'AUTHOR_URL', 'TIMEZONE') {
    $line = (Read-Text blog.conf).Split("`n") | Where-Object { $_ -like "$k=*" } | Select-Object -First 1
    if (-not $line) { throw "blog.conf needs $k" }
    $V[$k] = Html-Esc $line.Substring($k.Length + 1)
}
foreach ($k in 'TITLE', 'DESCRIPTION', 'DATE', 'SLUG', 'SHA1', 'POSTS', 'BODY') { $V[$k] = '' }

# --- templates ---------------------------------------------------------------
# Indent marked's flat output by $pad, one level deeper per list/blockquote;
# lines inside <pre> are left as they are
function Format-Html($html, $pad) {
    $out = @(); $depth = 0; $inpre = $false
    foreach ($l in $html.Split("`n")) {
        if ($inpre) { $out += $l; if ($l -match '</pre>') { $inpre = $false }; continue }
        $o = [regex]::Matches($l, '<(ul|ol|blockquote)>').Count
        $c = [regex]::Matches($l, '</(ul|ol|blockquote)>').Count
        if ($l -match '^</') { $depth -= $c }
        $out += if ($l) { $pad + ('    ' * $depth) + $l } else { $l }
        if ($l -match '^</') { $depth += $o } else { $depth += $o - $c }
        if ($l -match '^<pre' -and $l -notmatch '</pre>') { $inpre = $true }
    }
    $out -join "`n"
}
# Replace every {{KEY}} in the template with $V[KEY]. A placeholder alone on a
# line takes a multi-line value, indented like the line.
function Render($template) {
    $out = @()
    foreach ($line in (Read-Text $template).TrimEnd("`n").Split("`n")) {
        if ($line -match '^(\s*)\{\{([A-Z_]+)\}\}$') {
            if ($V[$matches[2]]) { $out += Format-Html $V[$matches[2]] $matches[1] }
            continue
        }
        foreach ($k in $V.Keys) { $line = $line.Replace("{{$k}}", $V[$k]) }
        $out += $line
    }
    ($out -join "`n") + "`n"
}

# --- index.html, sitemap.xml, feed.xml -------------------------------------
function Update-Indexes {
    $posts = foreach ($md in Get-ChildItem content/*.md) {
        $m = (Read-Post $md.FullName).Meta
        if (Test-Path "posts/$($m.slug)/index.html") {
            [pscustomobject]@{ date = $m.date; slug = $m.slug; title = Html-Esc $m.title; desc = Html-Esc $m.description }
        }
    }
    $posts = @($posts | Sort-Object date, slug -Descending)
    $latest = if ($posts) { $posts[0].date }

    $V.POSTS = ($posts | ForEach-Object { "<li><time datetime=`"$($_.date)`">$($_.date)</time> <a href=`"posts/$($_.slug)/`">$($_.title)</a></li>" }) -join "`n"
    Write-Text index.html (Render scripts/index.template.html)

    $homeMod = if ($latest) { "        <lastmod>$latest</lastmod>`n" } else { '' }
    $urls = $posts | ForEach-Object { "    <url>`n        <loc>$($V.SITE_URL)/posts/$($_.slug)/</loc>`n        <lastmod>$($_.date)</lastmod>`n    </url>`n" }
    Write-Text sitemap.xml ((@"
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    <url>
        <loc>$($V.SITE_URL)/</loc>
$homeMod    </url>

"@ + ($urls -join '') + "</urlset>`n") -replace "`r`n", "`n")

    $tz = $V.TIMEZONE
    $entries = $posts | ForEach-Object { @"
    <entry>
        <title>$($_.title)</title>
        <link rel="alternate" type="text/html" href="$($V.SITE_URL)/posts/$($_.slug)/"/>
        <id>$($V.SITE_URL)/posts/$($_.slug)/</id>
        <published>$($_.date)T00:00:00$tz</published>
        <updated>$($_.date)T00:00:00$tz</updated>
        <summary>$($_.desc)</summary>
    </entry>

"@ }
    $updated = if ($latest) { $latest } else { '1970-01-01' }
    Write-Text feed.xml ((@"
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xml:lang="$($V.SITE_LANG)">
    <title>$($V.SITE_TITLE)</title>
    <subtitle>$($V.SITE_DESCRIPTION)</subtitle>
    <link rel="alternate" type="text/html" href="$($V.SITE_URL)/"/>
    <link rel="self" type="application/atom+xml" href="$($V.SITE_URL)/feed.xml"/>
    <id>$($V.SITE_URL)/</id>
    <updated>${updated}T00:00:00$tz</updated>
    <author>
        <name>$($V.AUTHOR_NAME)</name>
        <uri>$($V.AUTHOR_URL)</uri>
    </author>

"@ + ($entries -join '') + "</feed>`n") -replace "`r`n", "`n")
}

# --- one post --------------------------------------------------------------
function Publish-Post($md) {
    $m = (Read-Post $md).Meta
    foreach ($k in 'title', 'date', 'slug', 'description') { if (-not $m[$k]) { throw "${md}: front matter needs $k" } }
    if ($m.slug -notmatch '^[a-z0-9-]+$') { throw "${md}: slug must be lowercase a-z, 0-9, hyphens: $($m.slug)" }
    if ($m.date -notmatch '^\d{4}-\d{2}-\d{2}$') { throw "${md}: date must be YYYY-MM-DD: $($m.date)" }
    $slug = $m.slug
    $action = if (Test-Path "posts/$slug/index.html") { 'edit' } else { 'publish' }
    "$action $slug"

    # Images: every ![alt](src) not already under assets/posts/<slug>/ is fetched
    # into the next free number there and the Markdown is rewritten to use it.
    # Fenced code blocks and inline code are skipped when looking for them.
    $dir = "assets/posts/$slug"
    $text = Read-Text $md
    while ($true) {
        $scan = [regex]::Replace($text, '(?s)^```.*?^```', '', 'Multiline') -replace '`[^`]*`', ''
        $img = [regex]::Matches($scan, '!\[[^\]]*\]\(([^)\s]+)') | Where-Object { $_.Groups[1].Value -notlike "../$dir/*" } | Select-Object -First 1
        if (-not $img) { break }
        $src = $img.Groups[1].Value
        New-Item -ItemType Directory -Force $dir | Out-Null
        $n = [int](Get-ChildItem $dir | ForEach-Object { if ($_.Name -match '^\d+') { [int]$matches[0] } } | Measure-Object -Maximum).Maximum + 1
        $ext = [IO.Path]::GetExtension(($src -split '[?#]')[0])
        $dest = "$dir/{0:d2}$ext" -f $n
        if ($src -match '^https?://') { Invoke-WebRequest -UseBasicParsing -Uri $src -OutFile $dest }
        elseif ([IO.Path]::IsPathRooted($src)) { Copy-Item $src $dest }
        else { Copy-Item "content/$src" $dest }
        "  $src -> $dest"
        $text = $text.Replace("]($src", "](../$dest")
    }
    if (-not $m.ContainsKey('published')) {
        $close = $text.IndexOf("`n---`n")   # end of front matter; add the flag there
        $text = $text.Insert($close + 1, "published: true`n")
    }
    Write-Text $md $text
    $post = Read-Post $md

    # Render: ../assets/ becomes ../../assets/ because the page lives one level deeper than content/.
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "publish-$slug"
    Write-Text "$tmp.md" $post.Body
    Run npx -y $Marked -i "$tmp.md" -o "$tmp.html"
    $V.TITLE = Html-Esc $m.title; $V.DESCRIPTION = Html-Esc $m.description
    $V.DATE = $m.date; $V.SLUG = $slug; $V.SHA1 = Get-SourceHash $md
    $V.BODY = (Read-Text "$tmp.html").TrimEnd("`n").Replace('="../assets/', '="../../assets/')
    New-Item -ItemType Directory -Force "posts/$slug" | Out-Null
    Write-Text "posts/$slug/index.html" (Render scripts/post.template.html)

    Update-Indexes
    Run git add $md "posts/$slug" index.html sitemap.xml feed.xml
    if (Test-Path $dir) { Run git add $dir }
    if ($action -eq 'publish') { Confirm-Commit "feat(blog): publish $($m.title)" 'auto publish via script' }
    else { Confirm-Commit "fix(blog): edit $($m.title)" 'auto edit via script' }
}

function Unpublish-Post($md) {
    $m = (Read-Post $md).Meta
    "delete $($m.slug)"
    Run git rm -rq "posts/$($m.slug)"
    Update-Indexes
    Run git add $md index.html sitemap.xml feed.xml
    Confirm-Commit "chore(blog): delete $($m.title)" 'auto delete via script'
}

# Show what is staged, ask, commit or stop
function Confirm-Commit($subject, $body) {
    git status --short
    $answer = Read-Host "Commit `"$subject`"? [y/N]"
    if ("$answer" -notmatch '^[yY]$') { 'left staged, not committed'; exit 1 }
    $msg = Join-Path ([IO.Path]::GetTempPath()) 'publish.msg'
    Write-Text $msg "$subject`n`n$body`n"
    Run git commit -q -F $msg
    "  committed: $subject"
}

$count = 0
foreach ($md in Get-ChildItem content/*.md) {
    $m = (Read-Post $md.FullName).Meta
    if ($m.published -eq 'false') {
        if (-not (Test-Path "posts/$($m.slug)/index.html")) { continue }
        Unpublish-Post $md.FullName
    } else {
        if ((Get-SourceHash $md.FullName) -eq (Get-PageHash $m.slug)) { continue }
        Publish-Post $md.FullName
    }
    $count++
}

# blog.conf or index.template.html may have changed without any post changing
Update-Indexes
Run git add index.html sitemap.xml feed.xml
git diff --cached --quiet -- index.html sitemap.xml feed.xml
if ($LASTEXITCODE) {
    Confirm-Commit 'chore(blog): rebuild index' 'auto rebuild via script'
    $count++
}
"$count change(s)"
