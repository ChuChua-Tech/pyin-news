# Contributing to PYIN News

Bug reports, accessibility feedback, source corrections, and focused pull
requests are welcome through GitHub Issues. General feedback and source ideas
can also be sent to `pyin-news-feedback@chuchua.tech`.

## Source proposals

A proposed source should expose a public RSS or Atom endpoint, identify its
publisher clearly, publish substantive news or analysis, and return parseable
items in a direct fetch. Inclusion describes availability and subject matter;
it is not an endorsement or a claim of neutrality.

Please include the publisher name, feed URL, country or region, language, and a
brief reason it adds useful coverage. Do not include proprietary political-bias
ratings.

## Changes

Keep the plugin dependency-light and compatible with Omarchy's active theme.
Before proposing a change, run:

```bash
python -m py_compile bin/chuchua-news
omarchy plugin validate .
```

Changes to ranking should remain deterministic, explainable, and model-free.
Changes involving network requests, subprocesses, stored personal data, or AI
providers must be documented in the README.

## Security reports

Please do not publish a suspected vulnerability before it can be assessed.
Send a concise report to `hello@chuchua.tech`, including affected versions and
reproduction steps where possible.
