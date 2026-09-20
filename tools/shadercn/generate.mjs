// Source: shadcn-labs/shadercn edf7412ac6f7b377b695ca2b2d14535a3be85d44.
// Keep the upstream shader notices: XorDev shaders are non-commercial, attributed.
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { transformAsync } from '@babel/core';
import { build } from 'esbuild';
import { translate } from 'naga-wasm';
import { d } from 'typegpu';

const root = path.dirname(fileURLToPath(import.meta.url));
const output = path.resolve(root, '../../glance/Resources/ShaderOrbCatalog.json');
await fs.mkdir(path.join(root, '.generated'), { recursive: true });
const catalog = [];
for (let n = 1; n <= 33; n++) {
  const id = `orb-${String(n).padStart(2, '0')}`;
  const entry = path.join(root, 'upstream', id, 'meta.ts');
  const bundle = path.join(root, '.generated', `${id}.mjs`);
  await build({
    entryPoints: [entry], outfile: bundle, bundle: true, platform: 'node', format: 'esm',
    packages: 'external',
    plugins: [{ name: 'typegpu', setup(b) {
      b.onResolve({ filter: /^@\/components\/orbs\// }, a => ({ path: path.join(root, 'upstream', a.path.replace('@/components/orbs/', '') + '.ts') }));
      b.onLoad({ filter: /gpu\.ts$/ }, async a => {
        const result = await transformAsync(await fs.readFile(a.path, 'utf8'), {
          filename: a.path, presets: ['@babel/preset-typescript'], plugins: ['unplugin-typegpu/babel'],
        });
        return { contents: result.code, loader: 'js' };
      });
    }}],
  });
  const exports = await import(bundle);
  const variant = exports[`orb${String(n).padStart(2, '0')}Orb`];
  const vertex = `
struct GlanceVertex { @builtin(position) position: vec4f, @location(0) uv: vec2f }
@vertex fn glanceVertex(@builtin(vertex_index) index: u32) -> GlanceVertex {
  var positions = array<vec2f, 3>(vec2f(-1, -1), vec2f(3, -1), vec2f(-1, 3));
  let p = positions[index];
  return GlanceVertex(vec4f(p, 0, 1), vec2f((p.x + 1) * 0.5, (1 - p.y) * 0.5));
}`;
  // naga-wasm leaves resource assignments to the host. Each orb has exactly
  // one uniform buffer; bind it to Metal fragment buffer 0.
  const notice = '// Shader by XorDev (https://x.com/XorDev), via shadercn / Orbkit.\n// Non-commercial use only, with attribution; keep this notice with the file.\n';
  const metal = notice + translate({ from: 'wgsl', to: 'msl', source: variant.shader + vertex, options: { langVersion: [2, 0] } })
    .replaceAll('[[user(fake0)]]', '[[buffer(0)]]');
  const slots = Object.fromEntries(Object.keys(variant.uniforms.propTypes).map(key =>
    [key, d.memoryLayoutOf(variant.uniforms, fields => fields[key]).offset / 4]));
  const fragment = metal.match(/fragment\s+\w+\s+(\w+)\(/)?.[1];
  if (!fragment) throw new Error(`No fragment entry for ${id}`);
  catalog.push({ id, label: variant.label, note: variant.note, params: variant.params,
    colors: variant.colors, statePresets: variant.statePresets ?? {}, stateColors: variant.stateColors ?? {},
    slots, floatCount: Math.ceil(d.sizeOf(variant.uniforms) / 16) * 4, fragment, metal });
  console.log(`${id}: ${fragment}, ${metal.length} bytes`);
}
await fs.writeFile(output, JSON.stringify(catalog));
console.log(`Wrote ${catalog.length} shaders to ${output}`);
