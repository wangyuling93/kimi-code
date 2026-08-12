import { Container, compositeTuiLine, type RenderContext } from "../tui.ts";
import { visibleWidth } from "../utils.ts";
import { allocateStackSizes, Stack, type StackChild, type StackOptions, visibleStackEntries } from "./stack.ts";

export class HStack extends Stack {
	protected readonly layoutType = "hstack" as const;

	constructor(children: StackChild[] = [], options: StackOptions = {}) {
		super(children, options);
	}

	override render(width: number, ctx?: RenderContext): string[] {
		const safeWidth = Math.max(1, width);
		const viewport = { width: safeWidth, height: Number.MAX_SAFE_INTEGER };
		const entries = visibleStackEntries(this.entries, viewport);
		if (entries.length === 0) return [];

		const intrinsicWidths = entries.map((entry) => {
			const lines = entry.component.render(safeWidth);
			return lines.reduce((max, line) => Math.max(max, visibleWidth(line)), 0);
		});
		const widths = allocateStackSizes(entries, intrinsicWidths, safeWidth, this.gap);
		const measured = entries.map((entry, index) =>
			widths[index] === 0 ? [] : entry.component.render(widths[index]!),
		);
		const height = measured.reduce((max, lines) => Math.max(max, lines.length), 0);
		const result = Array.from({ length: height }, () => "");
		let x = 0;
		for (let index = 0; index < measured.length; index++) {
			const lines = measured[index]!;
			const childWidth = widths[index]!;
			let offset = 0;
			if (this.align === "center") offset = Math.floor((height - lines.length) / 2);
			else if (this.align === "end") offset = height - lines.length;
			// Render again with the context position so leaf components can
			// register mouse hit regions at their final box origin.
			const childCtx = ctx ? { row: ctx.row + offset, col: ctx.col + x, regions: ctx.regions } : undefined;
			const childLines =
				childCtx && childWidth > 0 ? entries[index]!.component.render(childWidth, childCtx) : lines;
			if (childCtx && childWidth > 0 && !(entries[index]!.component instanceof Container)) {
				childCtx.regions.push({
					component: entries[index]!.component,
					rowStart: childCtx.row,
					colStart: childCtx.col,
					rowEnd: childCtx.row + childLines.length,
					colEnd: childCtx.col + childWidth,
				});
			}
			for (let row = 0; row < childLines.length; row++) {
				const target = row + offset;
				if (target < 0 || target >= result.length) continue;
				result[target] = compositeTuiLine(result[target]!, childLines[row]!, x, childWidth, safeWidth);
			}
			x += childWidth + this.gap;
		}
		return result;
	}
}
