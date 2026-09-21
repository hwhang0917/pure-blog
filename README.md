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

Create `content/<anything>.md` with a front matter block:

```markdown
---
title: Hello, world
date: 2026-09-21
slug: hello-world
description: One or two sentences for search results and the feed.
---

## First heading

Body starts here. Headings start at `##` because the title is the `<h1>`.
```

- `slug` becomes the URL: `posts/hello-world/`. Lowercase letters, digits and hyphens only.
- `published` is optional. The script adds `published: true` on first publish.
  Set `published: false` to keep a draft off the site; if the post was already
  published, its page is removed and a delete commit is proposed.
- Raw HTML passes through, so a post can carry `<script>`, `<style>` or `<canvas>`.

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
