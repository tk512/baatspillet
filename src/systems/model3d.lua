-- Live 3D boats: a low-poly OBJ rendered in real 3D every frame, so it rotates
-- smoothly as you steer instead of snapping between baked frames.
--
-- The OBJ is parsed once into a static Mesh (position, material colour, flat
-- face normal per corner). Each draw a vertex shader yaw-rotates it, projects
-- it through the same iso camera the baked-frame pipeline used (orthographic,
-- Blender rot X=60 Z=45), lights it, and depth-tests into a shared offscreen
-- MSAA canvas. That canvas is blitted like any boat sprite, so the world's 2D
-- painter ordering never learns a 3D model was involved.
--
-- Placeholder-first: has()/draw() return false with no .obj or no shader, and
-- the caller falls back to its code-drawn boat.
--
-- Yaw: for this camera the model yaw matching heading `a` is exactly -a. A
-- model whose bow isn't along +X is corrected by `modelYaw` in boats.lua.

local config = require("src.config")
local Assets = require("src.assets")
local Iso    = require("src.systems.iso")

local Model3D = {}

-- Base colours keyed by the OBJ's `usemtl` names, for art direction or a model
-- shipped without its .mtl. Anything not named here takes its Kd from
-- assets/models/<name>.mtl, then a neutral grey.
local PALETTE = {
    Wood      = { 0.52, 0.36, 0.21 },
    DarkWood  = { 0.34, 0.22, 0.13 },
    LightWood = { 0.70, 0.53, 0.32 },
    Red       = { 0.78, 0.20, 0.16 },
    White     = { 0.93, 0.89, 0.79 },
}
local FALLBACK = { 0.62, 0.60, 0.58 }

-- Per-model overrides, highest priority. Scoped by model name because voxel
-- exports use generic material names ("mat17") that differ per model.
local MODEL_PALETTE = {
    toffe = {
        ["13___Default"] = { 0.24, 0.42, 0.66 },  -- hull sides: friendly blue
        ["07___Default"] = { 0.78, 0.20, 0.15 },  -- hull bottom: livelier red
    },
}

-- Load-time geometry stripping, opt-in PER MODEL and never automatic: voxel
-- exports are hundreds of disconnected boxes, and a blanket rule eats funnels
-- and fenders.
--   SIDE_GEAR  components fully off one side of the hull (the viking oars)
--   THIN       wire-thin components (rigging) -- sub-pixel at ~100px, so they
--              can only shimmer
local STRIP_SIDE_GEAR = { vikingskipet = true }
local STRIP_THIN      = { toffe = true }

local CANVAS = 512      -- offscreen render size; blit scales it to spriteWidth
local MARGIN = 0.04     -- content margin inside the canvas
local WHITE  = { 1, 1, 1 }

-- position + colour use the built-in locations (0, 2); the flat face normal
-- rides along as a custom attribute at 3
local FORMAT = {
    { name = "VertexPosition", format = "floatvec3",  location = 0 },
    { name = "VertexTexCoord", format = "floatvec2",  location = 1 },
    { name = "VertexColor",    format = "unorm8vec4", location = 2 },
    { name = "VertexNormal",   format = "floatvec3",  location = 3 },
}

-- Iso camera basis, Z-up: RIGHT/UP span the screen, FWD is the view direction
-- (larger dot = farther). Duplicated in the shader below -- keep them in sync.
local UPZ, UPG = 0.8660254, 0.3535534   -- UP's height / ground components

local SHADER_SRC = [[
varying float v_shade;

#ifdef VERTEX
layout (location = 3) in vec3 VertexNormal;
uniform float u_yaw;
uniform float u_depth;   // per-model: clip-depth units per model unit

const vec3 RIGHT = vec3( 0.7071068, 0.7071068, 0.0);
const vec3 UP    = vec3(-0.3535534, 0.3535534, 0.8660254);
const vec3 FWD   = vec3(-0.6123724, 0.6123724, -0.5);
const vec3 SUN   = vec3(-0.3452969, 0.2466407, 0.9055458); // normalized
const float AMBIENT = 0.50, DIFFUSE = 0.55;

vec4 position(mat4 clipSpaceFromLocal, vec4 v)
{
    float s = sin(u_yaw), c = cos(u_yaw);
    vec3 p = vec3(v.x * c - v.y * s, v.x * s + v.y * c, v.z);
    vec3 n = vec3(VertexNormal.x * c - VertexNormal.y * s,
                  VertexNormal.x * s + VertexNormal.y * c,
                  VertexNormal.z);
    if (dot(n, FWD) > 0.0) n = -n;      // double-sided (the sail is a plane)
    v_shade = clamp(AMBIENT + DIFFUSE * max(dot(n, SUN), 0.0), 0.0, 1.0);

    vec4 o = clipSpaceFromLocal * vec4(dot(p, RIGHT), -dot(p, UP), 0.0, 1.0);
    // Depth for the z-test, normalized per model — model units vary wildly
    // between exports (the viking ship is ~4 units long, some are ~900), and
    // an un-normalized depth lands outside the clip volume and CLIPS most
    // of the mesh away (renders as a thin "wireframe" slice).
    o.z = dot(p, FWD) * u_depth;
    return o;
}
#endif

#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc)
{
    // Untextured models get a 1x1 white texture, so this is a no-op for them.
    vec4 t = Texel(tex, tc);
    return vec4(t.rgb * color.rgb * v_shade, t.a * color.a);
}
#endif
]]

local cache = {}          -- name -> model table, or false = tried and absent
local canvas, shader      -- lazy shared render target + shader

local whiteImg
local function whiteTexture()
    if not whiteImg then
        local d = love.image.newImageData(1, 1)
        d:setPixel(0, 0, 1, 1, 1, 1)
        whiteImg = love.graphics.newImage(d)
    end
    return whiteImg
end

-- Parse the OBJ into a flat-shaded triangle mesh. OBJ is Y-up, so (x, y, z)
-- becomes Z-up (x, -z, y). The model is centred and lifted so its keel sits at
-- z = 0, the waterline, wherever the exporter put the origin. Polygons are
-- fan-triangulated, every corner carrying its face normal; mixed windings are
-- fine, the shader flips normals toward the camera.
local function parseObj(text)
    local verts, vts, faces, mtl, obj = {}, {}, {}, nil, nil
    for line in text:gmatch("[^\r\n]+") do
        local x, y, z = line:match("^v%s+(%S+)%s+(%S+)%s+(%S+)")
        if x then
            verts[#verts + 1] = { tonumber(x), -tonumber(z), tonumber(y) }
        elseif line:find("^vt%s") then
            local u, v = line:match("^vt%s+(%S+)%s+(%S+)")
            vts[#vts + 1] = { tonumber(u), 1 - tonumber(v) }  -- OBJ v runs bottom-up
        elseif line:find("^o%s") then
            obj = line:match("^o%s+(%S+)")
        elseif line:find("^usemtl") then
            mtl = line:match("^usemtl%s+(%S+)")
        elseif line:find("^f%s") then
            local idx, tex = {}, {}
            for tok in line:gmatch("%s(%S+)") do
                idx[#idx + 1] = tonumber(tok:match("^(%-?%d+)"))
                tex[#tex + 1] = tonumber(tok:match("^%-?%d+/(%d+)"))
            end
            for i = 2, #idx - 1 do
                faces[#faces + 1] = { idx[1], idx[i], idx[i + 1], mtl,
                    tex[1], tex[i], tex[i + 1], obj }
            end
        end
    end

    local minx, maxx = math.huge, -math.huge
    local miny, maxy = math.huge, -math.huge
    local minz = math.huge
    for _, v in ipairs(verts) do
        minx, maxx = math.min(minx, v[1]), math.max(maxx, v[1])
        miny, maxy = math.min(miny, v[2]), math.max(maxy, v[2])
        minz = math.min(minz, v[3])
    end
    local cx, cy = (minx + maxx) / 2, (miny + maxy) / 2
    for _, v in ipairs(verts) do
        v[1], v[2], v[3] = v[1] - cx, v[2] - cy, v[3] - minz
    end
    return verts, faces, vts
end

-- Kd colours from assets/models/<name>.mtl; missing file -> empty table
local function loadMtl(name)
    local colors = {}
    local text = love.filesystem.read("assets/models/" .. name .. ".mtl")
    if not text then return colors end
    local cur
    for line in text:gmatch("[^\r\n]+") do
        local m = line:match("^%s*newmtl%s+(%S+)")
        if m then
            cur = m
        elseif cur then
            local r, g, b = line:match("^%s*Kd%s+(%S+)%s+(%S+)%s+(%S+)")
            if r then colors[cur] = { tonumber(r), tonumber(g), tonumber(b) } end
        end
    end
    return colors
end

-- Union-find the mesh into connected components (these exports don't share
-- vertices between parts) with per-component bounds — raw material for the
-- strip rules.
local function findComponents(verts, faces)
    local parent = {}
    for i = 1, #verts do parent[i] = i end
    local function find(a)
        while parent[a] ~= a do
            parent[a] = parent[parent[a]]
            a = parent[a]
        end
        return a
    end
    for _, f in ipairs(faces) do
        local r = find(f[1])
        parent[find(f[2])] = r
        parent[find(f[3])] = r
    end

    local comps = {}
    for i = 1, #verts do
        local r = find(i)
        local c = comps[r]
        if not c then
            c = { count = 0, ids = {},
                minx = math.huge, maxx = -math.huge,
                miny = math.huge, maxy = -math.huge,
                minz = math.huge, maxz = -math.huge }
            comps[r] = c
        end
        local v = verts[i]
        c.count = c.count + 1
        c.minx, c.maxx = math.min(c.minx, v[1]), math.max(c.maxx, v[1])
        c.miny, c.maxy = math.min(c.miny, v[2]), math.max(c.maxy, v[2])
        c.minz, c.maxz = math.min(c.minz, v[3]), math.max(c.maxz, v[3])
        c.ids[#c.ids + 1] = i
    end
    return comps
end

-- The set of vertex indices this model's opt-in strip rules drop (empty for
-- models with no rules enabled).
local function stripVerts(name, verts, faces)
    local strip = {}
    if not (STRIP_SIDE_GEAR[name] or STRIP_THIN[name]) then return strip end

    local D = 0   -- the model's largest dimension, for the thinness rule
    local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    for _, v in ipairs(verts) do
        for k = 1, 3 do
            lo[k], hi[k] = math.min(lo[k], v[k]), math.max(hi[k], v[k])
        end
    end
    for k = 1, 3 do D = math.max(D, hi[k] - lo[k]) end

    for _, c in pairs(findComponents(verts, faces)) do
        local kill = STRIP_SIDE_GEAR[name] and c.count < 50
            and (c.minx > 0.1 or c.maxx < -0.1)
        if not kill and STRIP_THIN[name] then
            local d1, d2, d3 = c.maxx - c.minx, c.maxy - c.miny, c.maxz - c.minz
            if d1 > d2 then d1, d2 = d2, d1 end
            if d2 > d3 then d2, d3 = d3, d2 end
            if d1 > d2 then d1, d2 = d2, d1 end
            kill = d2 < D * 0.015          -- two smallest dims both wire-thin
        end
        if kill then
            for _, i in ipairs(c.ids) do strip[i] = true end
        end
    end
    return strip
end

local shaderFailed
local function ensureShader()
    if shader then return true end
    if shaderFailed then return false end     -- fall back to placeholder art
    local ok, s = pcall(love.graphics.newShader, SHADER_SRC)
    if ok then shader = s else shaderFailed = true end
    return shader ~= nil
end

-- One triangle -> three FORMAT-ordered vertex rows appended to `data`, flat-
-- shaded with the face normal. ta/tb/tc are vt indices (nil = no UVs).
local function emitFace(data, a, b, c, ta, tb, tc, col, vts)
    local e1x, e1y, e1z = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local e2x, e2y, e2z = c[1] - a[1], c[2] - a[2], c[3] - a[3]
    local nx = e1y * e2z - e1z * e2y
    local ny = e1z * e2x - e1x * e2z
    local nz = e1x * e2y - e1y * e2x
    local l = math.sqrt(nx * nx + ny * ny + nz * nz)
    if l > 0 then nx, ny, nz = nx / l, ny / l, nz / l end
    local ua, ub, uc = vts[ta or -1], vts[tb or -1], vts[tc or -1]
    data[#data + 1] = { a[1], a[2], a[3], ua and ua[1] or 0, ua and ua[2] or 0,
        col[1], col[2], col[3], 1, nx, ny, nz }
    data[#data + 1] = { b[1], b[2], b[3], ub and ub[1] or 0, ub and ub[2] or 0,
        col[1], col[2], col[3], 1, nx, ny, nz }
    data[#data + 1] = { c[1], c[2], c[3], uc and uc[1] or 0, uc and uc[2] or 0,
        col[1], col[2], col[3], 1, nx, ny, nz }
end

local function loadModel(name)
    local text = love.filesystem.read("assets/models/" .. name .. ".obj")
    if not text then return false end
    if not ensureShader() then return false end

    local verts, faces, vts = parseObj(text)
    local strip = stripVerts(name, verts, faces)
    local mtl = loadMtl(name)
    local override = MODEL_PALETTE[name]
    -- A texture (assets/models/<name>.png) carries the colours of every
    -- material not explicitly overridden — textured exports set Kd to black,
    -- so the .mtl chain would paint them as silhouettes.
    local img = Assets.image("models/" .. name .. ".png")

    -- Canvas layout, from rotation-invariant bounds: over a full turn a vertex
    -- at ground radius r, height z spans u in +-r and v in 0.866z +- 0.5r.
    -- Stripped vertices don't count, or they'd pad the frame.
    local rmax, vmin, vmax = 0, math.huge, -math.huge
    for i, v in ipairs(verts) do
        if not strip[i] then
            local r = math.sqrt(v[1] * v[1] + v[2] * v[2])
            rmax = math.max(rmax, r)
            vmin = math.min(vmin, UPZ * v[3] - UPG * r)
            vmax = math.max(vmax, UPZ * v[3] + UPG * r)
        end
    end
    local ppu = CANVAS * (1 - 2 * MARGIN) / math.max(2 * rmax, vmax - vmin)
    local originY = CANVAS * (1 - MARGIN) + vmin * ppu   -- the waterline row (v = 0)

    local data = {}
    for _, f in ipairs(faces) do
        if not strip[f[1]] then    -- components are disjoint: one vertex decides
            local col = (override and override[f[4]]) or PALETTE[f[4]]
                or (img and WHITE) or mtl[f[4]] or FALLBACK
            emitFace(data, verts[f[1]], verts[f[2]], verts[f[3]],
                f[5], f[6], f[7], col, vts)
        end
    end

    local mesh = love.graphics.newMesh(FORMAT, data, "triangles", "static")
    if img then
        img:setFilter("linear", "linear")
        mesh:setTexture(img)
    else
        mesh:setTexture(whiteTexture())   -- keeps the shader's Texel a no-op
    end
    return {
        mesh    = mesh,
        ppu     = ppu,
        originY = originY,
        topY    = originY - vmax * ppu,
        botY    = CANVAS * (1 - MARGIN),
        -- keeps |clip z| well inside the volume whatever the model's units
        depth   = 0.2 / math.max(rmax, vmax, 1e-6),
    }
end

local function getModel(name)
    local m = cache[name]
    if m == nil then
        m = loadModel(name)
        cache[name] = m
    end
    return m or nil
end

function Model3D.has(name)
    return name ~= nil and getModel(name) ~= nil
end

-- Draw the model at ground point (gx, gy) heading `angle`, scaled so the
-- canvas maps to `width` on-screen pixels (same semantics as drawBoatFrames).
-- yawDeg is the per-model bow correction (boats.lua `modelYaw`). anchorFrac:
-- nil/absent anchors the waterline at the ground point (sailing); a fraction
-- anchors within the boat's height instead (0.5 = centred, for previews).
function Model3D.draw(name, gx, gy, angle, width, yawDeg, tint, anchorFrac)
    local m = getModel(name)
    if not m then return false end

    if not canvas then
        canvas = love.graphics.newCanvas(CANVAS, CANVAS, { msaa = 4 })
    end

    -- Render at the boat's true on-screen pixel size (measured from the
    -- current transform, camera zoom included), so canvas pixels map ~1:1 to
    -- screen pixels: no minification shimmer on thin details while sailing,
    -- and MSAA alone keeps the edges clean. f < 1 just uses a corner of the
    -- shared canvas.
    local x0, y0 = love.graphics.transformPoint(0, 0)
    local x1, y1 = love.graphics.transformPoint(1, 0)
    local zoom = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
    local wantPx = width or config.BOAT_SPRITE_WIDTH
    local f = math.max(16, math.min(CANVAS, wantPx * zoom)) / CANVAS

    -- Render pass: the model alone on the shared canvas, depth-tested.
    local prevCanvas = love.graphics.getCanvas()
    love.graphics.push("all")
    love.graphics.setCanvas({ canvas, depth = true })
    love.graphics.origin()
    love.graphics.clear(0, 0, 0, 0, false, true)
    love.graphics.setShader(shader)
    love.graphics.setDepthMode("lequal", true)
    love.graphics.setColor(1, 1, 1)
    shader:send("u_yaw", -angle + math.rad(yawDeg or 0))
    shader:send("u_depth", m.depth)
    love.graphics.translate(CANVAS / 2 * f, m.originY * f)
    love.graphics.scale(m.ppu * f)
    love.graphics.draw(m.mesh)
    love.graphics.pop()
    love.graphics.setCanvas(prevCanvas)

    -- Blit like any boat sprite.
    local sx, sy = Iso.project(gx, gy, 0)
    local s = wantPx / (CANVAS * f)
    local oy = m.originY
    if anchorFrac then oy = m.topY + (m.botY - m.topY) * anchorFrac end
    love.graphics.setColor(tint or WHITE)
    love.graphics.draw(canvas, sx, sy, 0, s, s, CANVAS / 2 * f, oy * f)
    return true
end

-- ---------------------------------------------------------------------------
-- Baked prop packs: one OBJ holding several small models side by side (e.g.
-- assets/models/trees.obj). The pack is split into variants by ground-x
-- clustering of connected components, each variant coloured by its `o` group
-- name (prefix-matched in palettes[k], cycling) and rendered ONCE through the
-- same iso camera into its own mipmapped Image. World props are static and
-- legion — they must never pay the live-3D render cost per frame.
-- Returns { { img, w, h, groundY }, ... } (groundY = the pixel row of the
-- ground plane, for bottom-anchoring), or nil when the pack file is absent
-- (placeholder-first: callers keep their code-drawn art).
function Model3D.bakeVariants(name, palettes, px)
    local text = love.filesystem.read("assets/models/" .. name .. ".obj")
    if not text or not ensureShader() then return nil end
    if not canvas then
        canvas = love.graphics.newCanvas(CANVAS, CANVAS, { msaa = 4 })
    end
    px = math.min(px or 96, CANVAS)

    local verts, faces, vts = parseObj(text)

    -- left-to-right clusters of connected components = the pack's variants
    local comps = {}
    for _, c in pairs(findComponents(verts, faces)) do comps[#comps + 1] = c end
    table.sort(comps, function(a, b) return a.minx + a.maxx < b.minx + b.maxx end)
    local eps = (comps[#comps].maxx - comps[1].minx) * 0.005
    local clusters = {}
    for _, c in ipairs(comps) do
        local cur = clusters[#clusters]
        if not (cur and c.minx < cur.maxx - eps) then   -- no x-overlap: new variant
            cur = { minx = c.minx, maxx = c.maxx, miny = c.miny, maxy = c.maxy,
                minz = c.minz, maxz = c.maxz, ids = {} }
            clusters[#clusters + 1] = cur
        end
        cur.minx, cur.maxx = math.min(cur.minx, c.minx), math.max(cur.maxx, c.maxx)
        cur.miny, cur.maxy = math.min(cur.miny, c.miny), math.max(cur.maxy, c.maxy)
        cur.minz, cur.maxz = math.min(cur.minz, c.minz), math.max(cur.maxz, c.maxz)
        for _, i in ipairs(c.ids) do cur.ids[i] = true end
    end

    -- face colour: the palette entry whose key prefixes the face's `o` group
    local function groupColor(pal, g)
        if g then
            for prefix, col in pairs(pal) do
                if g:sub(1, #prefix) == prefix then return col end
            end
        end
        return FALLBACK
    end

    local variants = {}
    for k, cl in ipairs(clusters) do
        local pal = palettes[((k - 1) % #palettes) + 1]
        local cx = (cl.minx + cl.maxx) / 2
        local cy = (cl.miny + cl.maxy) / 2
        -- recentred copies of this cluster's vertices (ground centre -> 0,
        -- lowest point -> the ground plane z = 0)
        local lv = {}
        for i in pairs(cl.ids) do
            local v = verts[i]
            lv[i] = { v[1] - cx, v[2] - cy, v[3] - cl.minz }
        end

        local data = {}
        for _, f in ipairs(faces) do
            if cl.ids[f[1]] then
                emitFace(data, lv[f[1]], lv[f[2]], lv[f[3]],
                    f[5], f[6], f[7], groupColor(pal, f[8]), vts)
            end
        end

        -- projected bounds at the baked yaw (static prop: no turn to allow for)
        local umin, umax, vmin, vmax = math.huge, -math.huge, math.huge, -math.huge
        for _, v in pairs(lv) do
            local u = (v[1] + v[2]) * 0.7071068
            local w = (-v[1] + v[2]) * 0.3535534 + v[3] * 0.8660254
            umin, umax = math.min(umin, u), math.max(umax, u)
            vmin, vmax = math.min(vmin, w), math.max(vmax, w)
        end
        local ppu = px * (1 - 2 * MARGIN) / math.max(umax - umin, vmax - vmin)
        local ox = px / 2 - (umin + umax) / 2 * ppu
        local groundY = px * (1 - MARGIN) + vmin * ppu

        local mesh = love.graphics.newMesh(FORMAT, data, "triangles", "static")
        mesh:setTexture(whiteTexture())

        local prevCanvas = love.graphics.getCanvas()
        love.graphics.push("all")
        love.graphics.setCanvas({ canvas, depth = true })
        love.graphics.origin()
        love.graphics.clear(0, 0, 0, 0, false, true)
        love.graphics.setShader(shader)
        love.graphics.setDepthMode("lequal", true)
        love.graphics.setColor(1, 1, 1)
        shader:send("u_yaw", 0)
        shader:send("u_depth", 0.2 / math.max(cl.maxx - cl.minx,
            cl.maxy - cl.miny, cl.maxz - cl.minz, 1e-6))
        love.graphics.translate(ox, groundY)
        love.graphics.scale(ppu)
        love.graphics.draw(mesh)
        love.graphics.pop()
        love.graphics.setCanvas(prevCanvas)

        -- read the baked corner back and keep it as a mipmapped Image (clean
        -- minification when the camera is zoomed out); free the scaffolding
        local full = love.graphics.readbackTexture
            and love.graphics.readbackTexture(canvas) or canvas:newImageData()
        local idata = love.image.newImageData(px, px)
        idata:paste(full, 0, 0, 0, 0, px, px)
        full:release()
        mesh:release()
        local img = love.graphics.newImage(idata, { mipmaps = true })
        img:setFilter("linear", "linear")
        img:setMipmapFilter("linear")
        idata:release()
        variants[k] = { img = img, w = px, h = px, groundY = groundY }
    end
    return variants
end

return Model3D
