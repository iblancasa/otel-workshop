/**
 * The two flavours of the workshop. Same shop, same steps, different
 * observability stack. Content lives under src/content/docs/<flavour>/.
 */
export const FLAVOURS = {
	otelite: {
		label: 'otelite',
		short: 'One small backend',
		hint: 'otelite: one binary shows logs, traces and metrics. 4 GB Docker VM. The default.',
	},
	cncf: {
		label: 'CNCF',
		short: 'Jaeger, Prometheus, Loki, Perses',
		hint: 'Jaeger for traces, Prometheus for metrics, Loki for logs, Perses for dashboards. 6 GB Docker VM.',
	},
} as const;

export type Flavour = keyof typeof FLAVOURS;
export const DEFAULT_FLAVOUR: Flavour = 'otelite';
export const STORAGE_KEY = 'workshop-flavour';

/** Flavour of a site path such as `/otel-workshop/cncf/steps/03-investigate/`, if any. */
export function flavourOfPath(pathname: string): Flavour | undefined {
	const m = pathname.match(/(?:^|\/)(otelite|cncf)(?:\/|$)/);
	return m ? (m[1] as Flavour) : undefined;
}
