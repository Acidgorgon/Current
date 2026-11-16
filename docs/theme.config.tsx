import React from 'react'
import { useRouter } from "next/router"
import { DocsThemeConfig } from 'nextra-theme-docs'

const config: DocsThemeConfig = {
  useNextSeoProps() {
		const { asPath } = useRouter()
		if (asPath !== "/") {
			return {
				titleTemplate: "%s – Current",
			}
		}
	},
  logo: (
      <>
        <img
          width="40"
          height="40"
          alt="Current"
          src="https://raw.githubusercontent.com/Acidgorgon/current/main/docs/public/letter.png"
        />
        <span style={{ marginLeft: '.6em', fontWeight: 700 }}>Current</span>
      </>
  ),
  project: {
    link: 'https://github.com/Acidgorgon/current',
  },
  docsRepositoryBase: 'https://github.com/Acidgorgon/current/tree/main/docs',
  footer: {
    text: 'Current, a fork of Blink by 1Axen',
  },
  head: (
    <>
      <link rel="shortcut icon" href="https://raw.githubusercontent.com/Acidgorgon/current/main/docs/public/letter.png" type="img/png"/>
      <meta property="og:description" content="A faster Roblox networking IDL compiler with two-way events, forked from Blink." />
    </>
  )
}

export default config
