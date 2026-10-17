// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { pluginLineNumbers } from '@expressive-code/plugin-line-numbers';
import { pluginCollapsibleSections } from '@expressive-code/plugin-collapsible-sections';

const REPO = 'https://github.com/iblancasa/otel-workshop';

// https://astro.build/config
export default defineConfig({
	site: 'https://iblancasa.github.io',
	base: '/otel-workshop',
	integrations: [
		starlight({
			title: 'The mystery of the slow API',
			description:
				'Hands-on workshop: find a production bottleneck with OpenTelemetry metrics, traces and logs, on your laptop.',
			social: [{ icon: 'github', label: 'GitHub', href: REPO }],
			editLink: { baseUrl: `${REPO}/edit/main/site/` },
			lastUpdated: true,
			customCss: ['./src/styles/custom.css'],
			// Starlight ships Expressive Code. https://expressive-code.com/
			expressiveCode: {
				themes: ['dracula', 'github-light'],
				plugins: [pluginLineNumbers(), pluginCollapsibleSections()],
				defaultProps: {
					showLineNumbers: false,
					overridesByLang: { 'python,java,js,ts': { showLineNumbers: true } },
				},
				styleOverrides: { borderRadius: '0.5rem' },
			},
			sidebar: [
				{ label: 'Start here', slug: 'start' },
				{ label: 'Before the workshop', slug: 'prepare' },
				{
					label: 'The workshop',
					items: [
						{ label: '0. The complaint', slug: 'steps/00-complaint' },
						{ label: '1. The stack', slug: 'steps/01-stack' },
						{ label: '2. Instrument', slug: 'steps/02-instrument' },
						{ label: '3. Metric, trace, log', slug: 'steps/03-investigate' },
						{ label: '4. Custom spans', slug: 'steps/04-custom-spans' },
						{ label: '5. Fix and prove', slug: 'steps/05-fix' },
						{ label: '6. Service graph', slug: 'steps/06-service-graph' },
					],
				},
				{
					label: 'Reference',
					items: [
						{ label: 'Commands', slug: 'reference/commands' },
						{ label: 'The metrics, explained', slug: 'reference/metrics' },
						{ label: 'No wifi', slug: 'reference/offline' },
						{ label: 'Troubleshooting', slug: 'reference/troubleshooting' },
					],
				},
			],
		}),
	],
});
