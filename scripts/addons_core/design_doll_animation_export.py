# -*- coding: utf-8 -*-
bl_info = {
    "name": "DesignDoll Animation PNG Export",
    "author": "OpenAI",
    "version": (1, 0, 0),
    "blender": (4, 0, 0),
    "location": "3D View > Sidebar (N) > アニメ出力",
    "description": "Render one DesignDoll model per PNG, using a camera from each collection",
    "category": "Render",
}

import os
import re
import bpy
from bpy.props import BoolProperty, EnumProperty, PointerProperty, StringProperty


# 'model1', 'model10', 'model1.001' (Blender's automatic duplicate suffix)
_FRAME_PATTERN = re.compile(r"^model(\d+)(?:\.\d{3,})?$", flags=re.IGNORECASE)
_INVALID_WIN_CHARS = re.compile(r'[<>:"/\\|?*\x00-\x1f]')
_WIN_DEVICE_NAMES = re.compile(r"^(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$", re.I)
_RENDERABLE_TYPES = {
    'MESH', 'CURVE', 'SURFACE', 'FONT', 'META', 'VOLUME',
    'POINTCLOUD', 'CURVES', 'GPENCIL', 'GREASEPENCIL',
}
_DEFAULT_OUTPUT = "//render_png"
_ENUM_CACHE = []
# Blender keeps references to callback strings: retain them across UI redraws.
_ENUM_STRING_POOL = {}


def frame_number(name):
    match = _FRAME_PATTERN.fullmatch(name)
    return int(match.group(1)) if match else None


def all_scene_collections(scene):
    """Only collections linked to the active scene; avoid repeats if multi-linked."""
    visited = set()
    result = []

    def visit(collection):
        key = collection.as_pointer()
        if key in visited:
            return
        visited.add(key)
        result.append(collection)
        for child in collection.children:
            visit(child)

    visit(scene.collection)
    return result


def candidates(scene):
    # A frame model must be a DIRECT member of its animation collection.
    # This avoids treating an umbrella parent collection as another animation.
    return [
        col for col in all_scene_collections(scene)
        if col != scene.collection
        and any(obj.type == 'CAMERA' for obj in col.objects)
        and any(obj.type == 'MESH' and frame_number(obj.name) is not None
                for obj in col.objects)
    ]


def natural_key(s):
    return [int(part) if part.isdigit() else part.casefold()
            for part in re.split(r'(\d+)', s)]


def list_animations(scene):
    return sorted(candidates(scene), key=lambda col: natural_key(col.name))


def enum_animations(self, context):
    global _ENUM_CACHE
    if context is None or context.scene is None:
        return _ENUM_CACHE or [('NONE', '(なし)', 'シーンを開いてください')]
    groups = list_animations(context.scene)
    _ENUM_CACHE = []
    for col in groups:
        _ENUM_STRING_POOL[col.name] = (col.name, col.name, 'カメラと連番モデル: ' + col.name)
        _ENUM_CACHE.append(_ENUM_STRING_POOL[col.name])
    if not _ENUM_CACHE:
        _ENUM_CACHE = [('NONE', '(対象なし)', 'カメラと model1 等のメッシュを含むコレクションがありません')]
    return _ENUM_CACHE


def collect_info(col):
    # Direct collection members only: prevents accidental frames in subcollections.
    frames = {}
    for obj in col.objects:
        if obj.type != 'MESH':
            continue
        idx = frame_number(obj.name)
        if idx is None:
            continue
        if idx in frames:
            raise ValueError(
                f'「{col.name}」のモデル番号 {idx} が重複: '
                f'{frames[idx].name} / {obj.name}。番号を重複させないでください。'
            )
        frames[idx] = obj

    if not frames:
        raise ValueError(f'「{col.name}」に model1 形式のメッシュがありません。')

    cams = [o for o in col.objects if o.type == 'CAMERA']
    if len(cams) != 1:
        raise ValueError(
            f'「{col.name}」にはカメラをちょうど1台入れてください（現在{len(cams)}台）。'
        )

    return cams[0], sorted(frames.items())


def safe_folder(name):
    folder = _INVALID_WIN_CHARS.sub('_', name).strip().rstrip('.')
    if not folder or _WIN_DEVICE_NAMES.fullmatch(folder):
        folder = '_' + folder
    return folder


def collection_ancestors(root, target):
    """Find one hierarchy path from root to target (inclusive)."""
    def find(cur, path):
        current = path + [cur]
        if cur == target:
            return current
        for child in cur.children:
            found = find(child, current)
            if found is not None:
                return found
        return None

    return find(root, [])


def layer_collection_ancestors(root, target):
    def find(cur, path):
        current = path + [cur]
        if cur.collection == target:
            return current
        for child in cur.children:
            found = find(child, current)
            if found is not None:
                return found
        return None

    return find(root, [])


def prepare_jobs(scene, selected, export_all, root_path, overwrite):
    animations = list_animations(scene)
    if not animations:
        raise ValueError('出力対象がありません。カメラと model1 等を同じコレクションに入れてください。')

    if export_all:
        todo = animations
    else:
        todo = [c for c in animations if c.name == selected]
        if not todo:
            raise ValueError('選択コレクションが見つかりません。ドロップダウンで選び直してください。')

    output_root = os.path.normpath(bpy.path.abspath(root_path.strip()))
    if not root_path.strip() or not output_root:
        raise ValueError('保存先フォルダを指定してください。')

    all_jobs = []
    folders = set()
    filenames = set()
    for col in todo:
        camera, frames = collect_info(col)
        folder = safe_folder(col.name)
        # Refuse ambiguous folder names (also important on Windows case-insensitive FS).
        folder_key = folder.casefold()
        if folder_key in folders:
            raise ValueError(f'保存先フォルダ名が衝突しています: {folder}')
        folders.add(folder_key)
        for number, obj in frames:
            dest = os.path.join(output_root, folder, f'{number:03d}.png')
            if dest.casefold() in filenames:
                raise ValueError(f'出力ファイル名が重複しています: {dest}')
            filenames.add(dest.casefold())
            if not overwrite and os.path.exists(dest):
                raise ValueError(
                    f'既存ファイルがあります: {dest}。削除するか「既存画像を上書き」を有効にしてください。'
                )
            all_jobs.append((col, camera, obj, dest))

    return all_jobs, output_root


class DDAX_PG_settings(bpy.types.PropertyGroup):
    animation: EnumProperty(
        name='アニメーション', description='モデルを含むコレクション', items=enum_animations
    )
    output_dir: StringProperty(
        name='保存先', description='この中にコレクション名のフォルダを作って保存',
        subtype='DIR_PATH', default=_DEFAULT_OUTPUT,
    )
    overwrite: BoolProperty(
        name='既存画像を上書き', description='同名PNGがあっても置き換える', default=False,
    )
    last_status: StringProperty(name='状態', default='未実行')


class DDAX_OT_batch_export(bpy.types.Operator):
    bl_idname = 'ddax.batch_export'
    bl_label = 'アニメーションPNG出力'
    bl_description = 'コレクションの各モデルを専用カメラで1枚ずつ保存します'
    bl_options = {'REGISTER'}

    export_all: BoolProperty(name='すべてのアニメーション', default=False)

    @classmethod
    def poll(cls, context):
        return context.scene is not None and context.mode == 'OBJECT'

    def execute(self, context):
        scene = context.scene
        settings = scene.ddax_settings
        if not bpy.data.filepath:
            # An absolute output path can work without saving, but saving the blend
            # first protects the camera and collection setup.
            self.report({'WARNING'}, '先に .blend ファイルを保存してください。')
            settings.last_status = '中止: .blend が未保存です'
            return {'CANCELLED'}

        try:
            jobs, root_path = prepare_jobs(
                scene, settings.animation, self.export_all,
                settings.output_dir, settings.overwrite,
            )
        except (ValueError, OSError) as exc:
            settings.last_status = f'中止: {str(exc)[:180]}'
            self.report({'ERROR'}, str(exc)[:900])
            return {'CANCELLED'}

        # Save all mutable render-related states, and restore even on exceptions.
        old_camera = scene.camera
        render = scene.render
        old_filepath = render.filepath
        old_use_file_extension = render.use_file_extension
        old_film_transparent = render.film_transparent
        image = render.image_settings
        old_file_format = image.file_format
        old_color_mode = image.color_mode
        old_color_depth = image.color_depth

        # Hide ALL other renderable geometry, including any reference model0 outside
        # animation collections; lights and cameras remain available.
        geometry = [o for o in scene.objects if o.type in _RENDERABLE_TYPES]
        old_obj_render = [(o, o.hide_render) for o in geometry]
        # Save camera visibility separately in case the user disabled it.
        group_cameras = set(cam for _, cam, _, _ in jobs)
        old_camera_render = [(cam, cam.hide_render) for cam in group_cameras]

        # If users hid a group for workspace organization, temporarily make its
        # collection path and view-layer path renderable. Preserve the original.
        altered_collections = {}
        altered_layers = {}
        for col, _cam, _obj, _dest in jobs:
            path = collection_ancestors(scene.collection, col)
            if not path:
                self.report({'ERROR'}, f'シーンにコレクションがありません: {col.name}')
                return {'CANCELLED'}
            for ancestor in path:
                if ancestor not in altered_collections:
                    altered_collections[ancestor] = ancestor.hide_render
            for view_layer in scene.view_layers:
                lpath = layer_collection_ancestors(view_layer.layer_collection, col)
                if lpath:
                    for layer_col in lpath:
                        key = layer_col.as_pointer()
                        if key not in altered_layers:
                            altered_layers[key] = (layer_col, layer_col.exclude)

        completed = 0
        wm = context.window_manager
        progress_started = False
        error = None
        try:
            for ancestor in altered_collections:
                ancestor.hide_render = False
            for layer_col, _old in altered_layers.values():
                layer_col.exclude = False

            render.use_file_extension = True
            render.film_transparent = True
            image.file_format = 'PNG'
            image.color_mode = 'RGBA'
            image.color_depth = '8'

            for cam, _old in old_camera_render:
                cam.hide_render = False
            for obj in geometry:
                obj.hide_render = True

            wm.progress_begin(0, len(jobs))
            progress_started = True
            current_obj = None
            for i, (_col, camera, obj, dest) in enumerate(jobs, start=1):
                # Only the current frame model is made renderable.
                if current_obj is not None:
                    current_obj.hide_render = True
                obj.hide_render = False
                current_obj = obj
                scene.camera = camera
                render.filepath = dest

                os.makedirs(os.path.dirname(dest), exist_ok=True)
                context.view_layer.update()
                result = bpy.ops.render.render('EXEC_DEFAULT', write_still=True)
                if 'FINISHED' not in result:
                    raise RuntimeError(f'レンダリングが完了しませんでした: {dest}')
                if not os.path.isfile(dest):
                    raise RuntimeError(f'保存されたPNGを確認できません: {dest}')
                completed += 1
                wm.progress_update(i)
                print(f'[DesignDoll PNG Export] {completed}/{len(jobs)}: {dest}')

        except Exception as exc:
            error = str(exc)
        finally:
            # Restore original scene state whether successful, failed, or interrupted.
            for obj, original in old_obj_render:
                try:
                    obj.hide_render = original
                except ReferenceError:
                    pass
            for cam, original in old_camera_render:
                try:
                    cam.hide_render = original
                except ReferenceError:
                    pass
            for layer_col, original in altered_layers.values():
                layer_col.exclude = original
            for col, original in altered_collections.items():
                col.hide_render = original
            scene.camera = old_camera
            render.filepath = old_filepath
            render.use_file_extension = old_use_file_extension
            render.film_transparent = old_film_transparent
            image.file_format = old_file_format
            image.color_mode = old_color_mode
            image.color_depth = old_color_depth
            context.view_layer.update()
            if progress_started:
                wm.progress_end()

        if error:
            settings.last_status = f'失敗: {completed}/{len(jobs)}枚  {error[:140]}'
            self.report({'ERROR'}, f'{completed}/{len(jobs)}枚で停止: {error[:400]}')
            return {'CANCELLED'}

        settings.last_status = f'完了: {completed}枚 → {root_path}'
        self.report({'INFO'}, f'PNG {completed}枚を保存しました')
        return {'FINISHED'}


class DDAX_PT_sidebar(bpy.types.Panel):
    bl_idname = 'VIEW3D_PT_ddax'
    bl_label = 'DesignDoll アニメーション出力'
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = 'アニメ出力'

    def draw(self, context):
        layout = self.layout
        scene = context.scene
        settings = scene.ddax_settings
        groups = list_animations(scene)

        layout.label(text=f'アニメーション: {len(groups)} コレクション')
        layout.prop(settings, 'animation')
        selected = next((c for c in groups if c.name == settings.animation), None)
        if selected:
            try:
                cam, frames = collect_info(selected)
                layout.label(text=f'{len(frames)}枚 / {cam.name}', icon='CAMERA_DATA')
            except ValueError as exc:
                layout.label(text=str(exc)[:55], icon='ERROR')
        layout.separator()
        layout.prop(settings, 'output_dir')
        layout.prop(settings, 'overwrite')
        layout.separator()
        col = layout.column(align=True)
        col.enabled = bool(groups) and context.mode == 'OBJECT'
        op = col.operator('ddax.batch_export', text='選択したアニメーションを出力', icon='IMAGE_DATA')
        op.export_all = False
        op = col.operator('ddax.batch_export', text='すべてのアニメーションを出力', icon='RENDER_ANIMATION')
        op.export_all = True
        layout.separator()
        layout.label(text='PNG / RGBA / 8bit・サイズは現在の設定')
        layout.label(text='model1 → 001.png / model10 → 010.png')
        layout.label(text=settings.last_status[:95], icon='INFO')


_CLASSES = (DDAX_PG_settings, DDAX_OT_batch_export, DDAX_PT_sidebar)


def register():
    for cls in _CLASSES:
        bpy.utils.register_class(cls)
    bpy.types.Scene.ddax_settings = PointerProperty(type=DDAX_PG_settings)


def unregister():
    del bpy.types.Scene.ddax_settings
    for cls in reversed(_CLASSES):
        bpy.utils.unregister_class(cls)


if __name__ == '__main__':
    register()