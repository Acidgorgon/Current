import { readFileSync } from 'node:fs'
import { defineConfig } from 'vitepress'
import { family } from './theme/family'

// Shared look and family links (theme/family.ts is identical on the Current, Ripple and Anchor sites)
const shared = family('current', '/Current/')

// Syntax highlighting for schema files (```blink code blocks)
const blinkGrammar = JSON.parse(readFileSync(new URL('./blink.tmLanguage.json', import.meta.url), 'utf8'))

export default defineConfig({
  ...shared.config,

  lang: 'en-US',
  title: 'Current',
  description: 'A faster Roblox networking IDL compiler with two-way events, forked from Blink.',

  markdown: {
    ...shared.config.markdown,
    languages: [{ ...blinkGrammar, name: 'blink', aliases: ['current'] }],
  },

  themeConfig: {
    ...shared.themeConfig,

    nav: [
      { text: 'Guide', link: '/guide/introduction', activeMatch: '^/guide/' },
      { text: 'Reference', link: '/reference/schema', activeMatch: '^/reference/' },
      shared.nav,
      {
        text: 'v0.1.0',
        items: [
          { text: 'Releases', link: 'https://github.com/Acidgorgon/Current/releases' },
          { text: 'Benchmark results', link: 'https://github.com/Acidgorgon/Current/blob/main/benchmark/harness/RESULTS.md' },
        ],
      },
    ],

    sidebar: {
      '/guide/': [
        {
          text: 'Guide',
          items: [
            { text: 'Introduction', link: '/guide/introduction' },
            { text: 'Installation', link: '/guide/installation' },
            { text: 'Getting started', link: '/guide/getting-started' },
            { text: 'Two-way events', link: '/guide/two-way-events' },
            { text: 'Migrating from Blink', link: '/guide/migrating-from-blink' },
            { text: 'Performance', link: '/guide/performance' },
            { text: 'Security', link: '/guide/security' },
            { text: 'Using with RBX Forge', link: '/guide/rbx-forge' },
          ],
        },
        { text: 'Reference', items: [{ text: 'Schema language →', link: '/reference/schema' }] },
      ],
      '/reference/': [
        {
          text: 'Reference',
          items: [
            { text: 'Schema language', link: '/reference/schema' },
            { text: 'Events', link: '/reference/events' },
            { text: 'Functions', link: '/reference/functions' },
            { text: 'Options', link: '/reference/options' },
            { text: 'Generated API', link: '/reference/generated-api' },
            { text: 'CLI', link: '/reference/cli' },
            { text: 'Studio plugin', link: '/reference/plugin' },
          ],
        },
        { text: 'Guide', items: [{ text: 'Introduction →', link: '/guide/introduction' }] },
      ],
    },

    socialLinks: [{ icon: 'github', link: 'https://github.com/Acidgorgon/Current' }],

    editLink: {
      pattern: 'https://github.com/Acidgorgon/Current/edit/main/docs/:path',
      text: 'Edit this page on GitHub',
    },
  },
})
