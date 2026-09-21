# Pure Blog

A blog that is nothing but HTML, CSS and Markdown. No framework, no build
step, no dependencies to keep up with. You write `content/*.md`, run one
script, and it renders the pages, updates the landing page, feed and sitemap,
and proposes a git commit. GitHub Pages serves the result as-is.

- `scripts/publish.sh` for Linux and macOS, `scripts/publish.ps1` for Windows.
  Same behavior, same output, byte for byte.
- Two HTML templates you own: `scripts/post.template.html` and
  `scripts/index.template.html`. Site-wide values live in `blog.conf`.
- Every rendered page records a hash of its sources, so editing a post, the
  config or the template re-renders exactly what changed.

## Requirements

- git
- node (the scripts run [marked](https://marked.js.org/) through `npx`, no install needed)
- bash 3.2+ and curl on Linux/macOS, or PowerShell 5.1+ on Windows

## Quick start

1. Click **Use this template** on GitHub, clone your new repo.
2. Edit `blog.conf`:

   ```
   SITE_URL=https://example.com
   SITE_TITLE=Pure Blog
   SITE_DESCRIPTION=A blog made of plain HTML, CSS and Markdown.
   SITE_LANG=en
   AUTHOR_NAME=Your Name
   AUTHOR_URL=https://github.com/you
   TIMEZONE=+00:00
   ```

   `SITE_URL` has no trailing slash. `TIMEZONE` is the offset used in the feed.
3. Publish the sample post (delete `content/hello-world.md` first if you would rather not):

   ```sh
   scripts/publish.sh        # Linux, macOS
   scripts/publish.ps1       # Windows
   ```

   The script shows what it staged and asks before each commit.
4. Push and turn on GitHub Pages, see below.

## GitHub Pages

The repo ships with `.github/workflows/deploy.yml`. On every push to `main`
that touches the site it copies everything except the paths in `.pagesignore`
into an artifact and deploys it. There is no build; what is in the repo is
what gets served.

1. In the repo on GitHub open **Settings**, then **Pages**.
2. Under **Build and deployment** set **Source** to **GitHub Actions**.
3. Push a commit, or run the **Deploy to GitHub Pages** workflow from the
   **Actions** tab. The first deploy takes a minute; the URL appears on the
   Pages settings page and on the workflow run.

Where the site ends up depends on the repo name:

| Repo name | URL | `SITE_URL` in `blog.conf` |
|---|---|---|
| `you.github.io` | `https://you.github.io/` | `https://you.github.io` |
| anything else, e.g. `blog` | `https://you.github.io/blog/` | `https://you.github.io/blog` |

The pages use relative links, so both layouts work. `SITE_URL` only feeds the
canonical URLs, the feed and the sitemap. Change it and run the publish script
once to regenerate them.

Pushes that only touch `content/`, `scripts/`, `blog.conf` or the README do
not trigger a deploy; the workflow's `paths-ignore` mirrors `.pagesignore`.

### Custom domain (optional)

1. At your DNS provider, point the domain at GitHub Pages:
   - a subdomain such as `blog.example.com`: a `CNAME` record to `you.github.io`
   - an apex domain such as `example.com`: `A` records to GitHub's Pages
     addresses, currently `185.199.108.153`, `185.199.109.153`,
     `185.199.110.153` and `185.199.111.153` (check
     [GitHub's docs](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site)
     for the current list)
2. In **Settings**, **Pages**, enter the domain under **Custom domain** and
   save. GitHub checks the DNS and issues a certificate; tick
   **Enforce HTTPS** once it is available.
3. Set `SITE_URL` in `blog.conf` to the new address, run the publish script,
   push.

With the Actions deployment the domain is stored in the repo settings, so a
`CNAME` file in the repo is not required. If you add one anyway, put only the
domain in it; it is deployed with the site and does no harm.

## Writing a post

Step by step, from blank file to live page:

1. Create a Markdown file in `content/`. The file name does not matter, the
   `slug` inside does:

   ```sh
   $EDITOR content/my-first-post.md
   ```

2. Start it with a front matter block, then the body:

   ```markdown
   ---
   title: My first post
   date: 2026-09-21
   slug: my-first-post
   description: One or two sentences for search results and the feed.
   ---

   ## First heading

   Body starts here. Headings start at `##` because the title is the `<h1>`.
   ```

   - `title`, `date` (`YYYY-MM-DD`), `slug` and `description` are required.
   - `slug` becomes the URL: `posts/my-first-post/`. Lowercase letters, digits
     and hyphens only.
   - Images can point anywhere, a URL or a file on disk; see below.

3. Preview if you like: any Markdown previewer works, and image paths resolve
   from `content/`. There is no local server to run.

4. Publish:

   ```sh
   scripts/publish.sh        # Linux, macOS
   scripts/publish.ps1       # Windows
   ```

   The script renders `posts/my-first-post/index.html`, fetches the images,
   adds `published: true` to the front matter, regenerates `index.html`,
   `feed.xml` and `sitemap.xml`, shows the staged files and asks:

   ```
   publish my-first-post
     https://example.com/shot.png -> assets/posts/my-first-post/01.png
   A  assets/posts/my-first-post/01.png
   M  content/my-first-post.md
   ...
   Commit "feat(blog): publish My first post"? [y/N] y
     committed: feat(blog): publish My first post
   1 change(s)
   ```

   Answer `y` to commit. Anything else leaves the files staged so you can
   inspect them, then run the script again.

5. Push. GitHub Pages deploys the commit and the post is live at
   `SITE_URL/posts/my-first-post/` a minute later.

   ```sh
   git push
   ```

To edit a post later, change the Markdown and run the script again; it
notices the change and proposes a `fix(blog): edit` commit. To take a post
down, set `published: false` in its front matter and run the script; the page
is removed and a `chore(blog): delete` commit is proposed. Drafts work the
same way: a new file with `published: false` is left alone until you remove
the line or set it to `true`.

### HTML, CSS and JavaScript in a post

Markdown allows raw HTML and the converter passes it through untouched, so a
post can carry its own markup, styles and scripts. Nothing in the scripts
needs to change.

**Inline, for small things.** Put the HTML where it should appear and the
script after it, so the element exists when the script runs:

```markdown
## Demo

<div id="out"></div>

<script>
  document.getElementById("out").textContent = `hi ${1 + 1}`;
</script>
```

Blank lines inside `<script>` and `<style>` are fine. Keep the opening tag at
the start of a line; indented HTML is treated as a code block by Markdown.

**A separate file, for bigger things.** Save it next to the post's images and
reference it relative to `content/`, the same way images are written:

```markdown
<script src="../assets/posts/my-first-post/app.js" defer></script>
<link rel="stylesheet" href="../assets/posts/my-first-post/app.css">
```

The publish script rewrites `../assets/` to `../../assets/` for the page, so
the link works both in a preview from `content/` and on the site. Only
`![…](…)` images are copied automatically; put other files into
`assets/posts/<slug>/` yourself. The script stages that folder with the post.

**Canvas, the sample post's way.** `content/hello-world.md` ends with a
`<canvas>` and a short inline script that animates it, and checks
`prefers-reduced-motion` to draw one still frame instead. Copy that pattern
for diagrams or demos.

Things to know:

- The rendered page indents the HTML to match the template, but lines inside
  `<pre>` are left alone, so code blocks are not affected. Script contents
  gain leading spaces, which JavaScript and CSS do not care about.
- Everything a post includes is served as-is from GitHub Pages: no bundling,
  no minification, no content security policy. Loading a library from a CDN
  with a plain `<script src="https://…">` works.
- Changing the Markdown, including its scripts, re-renders the page on the
  next run. Changing a file under `assets/posts/<slug>/` by hand does not
  touch the page; commit that file yourself.

### Images

Write images the normal way with any source:

```markdown
![A screenshot](https://example.com/shot.png)
![A photo](photo.jpg)            # relative to content/
![A diagram](/home/me/diagram.svg)
```

On publish the script downloads or copies each file into
`assets/posts/<slug>/` as `01.png`, `02.jpg`, ... and rewrites the Markdown to
point there. Previews from `content/` keep working because the rewritten path
is relative to that folder.

Anything else a post needs, a script file for example, goes into
`assets/posts/<slug>/` by hand and is referenced as
`../assets/posts/<slug>/file.js`. The script rewrites `../assets/` to the
page's depth.

## What a run does

For each `content/*.md`, in order:

| Situation | Action | Commit |
|---|---|---|
| No page yet | render | `feat(blog): publish <title>` |
| Page exists, sources changed | re-render | `fix(blog): edit <title>` |
| `published: false` and a page exists | remove `posts/<slug>/` | `chore(blog): delete <title>` |

"Sources" means the Markdown, `blog.conf` and `scripts/post.template.html`
together. Their SHA1 is written into the page as `<!-- source sha1: … -->`.
Changing the config or the template therefore re-renders every post, one
commit each.

After the posts, `index.html`, `feed.xml` and `sitemap.xml` are regenerated.
If they changed without any post changing, for example after editing
`scripts/index.template.html`, a `chore(blog): rebuild index` commit is proposed.

Answering anything but `y` at a prompt leaves the changes staged and stops.

## Templates

Both templates are plain HTML with `{{PLACEHOLDERS}}`:

| Placeholder | From | Available in |
|---|---|---|
| `SITE_URL`, `SITE_TITLE`, `SITE_DESCRIPTION`, `SITE_LANG`, `AUTHOR_NAME`, `AUTHOR_URL` | `blog.conf` | both |
| `TITLE`, `DESCRIPTION`, `DATE`, `SLUG` | front matter | post |
| `BODY` | rendered Markdown | post |
| `SHA1` | source hash, keep it in a comment | post |
| `POSTS` | `<li>` per post, newest first | index |

Text values are HTML-escaped once, so they are safe in attributes and text.
A placeholder alone on a line takes a multi-line value indented to match, which
is how `{{BODY}}` and `{{POSTS}}` end up nicely nested. Paths in the post
template are relative to `posts/<slug>/`.

`style.css` is yours. The generated markup uses these classes:
`.site-header`, `.site-title`, `.posts`, `.post`, `.post__title`,
`.post__meta`, `.prose`.

## Layout

```
blog.conf                   site-wide values
content/*.md                posts (source of truth)
scripts/publish.sh          publisher, POSIX
scripts/publish.ps1         publisher, Windows
scripts/post.template.html  post page template
scripts/index.template.html landing page template
posts/<slug>/index.html     generated
assets/posts/<slug>/        images copied by the script, anything else by hand
index.html feed.xml sitemap.xml   generated
style.css                   yours
.pagesignore                what the deploy leaves out of the site
```

## License

MIT, see `LICENSE`.
