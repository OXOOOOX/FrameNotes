import json
import sys

json_path = sys.argv[1]

with open(json_path, 'r', encoding='utf-8-sig') as f:
    data = json.load(f)

# Map frame timestamps to content sections
# Video structure: Intro → Lighting → Speaking → Equipment → Editing → Outro
frame_evaluations = {
    1:  ("accepted", '片头引入：展示"从这样变成这样"的对比效果，吸引观众继续观看'),
    6:  ("accepted", "三大模块总览：场景搭建、口播技巧、剪辑手法，清晰概括视频结构"),
    10: ("rejected", "与上一帧仅差2秒，内容重叠，且画面为同一说话场景"),
    15: ("accepted", "核心建议一：找墙角增加画面纵深感和层次感，关键场景布置技巧"),
    20: ("accepted", "具体布置：背后放书桌电脑，屏幕光作氛围光，具象化的操作指导"),
    24: ("accepted", "关键技巧：关掉房间灯，只用一盏面灯，人物从杂乱背景中跳出来"),
    29: ("accepted", "补充技巧：小台灯放身后解决背景太暗问题，展示前后对比效果"),
    34: ("accepted", "总结：无论相机还是手机，上述布光方案已适配所有赛道，段落收尾"),
    39: ("accepted", "口播技巧一：写大纲理清逻辑，避免跑题，适合话多的人"),
    43: ("accepted", "口播技巧二：准备逐字稿，面对镜头说不出来时的解决方案"),
    48: ("accepted", "口播技巧三：背一段录一段，看一句录一句，切换视角丰富画面"),
    53: ("accepted", "设备推荐：DJI Mic 3领夹麦，解决音质问题，声音质感提升"),
    57: ("accepted", "Mic 3功能：自动增益调节、音色预设（常规档/明亮档），声音更通透"),
    62: ("accepted", "户外场景：配合Action 6和Osmo Audio生态直连，户外录音轻松"),
    67: ("accepted", "降噪功能：Mic 3两档降噪，嘈杂环境也能收录高质量声音"),
    71: ("rejected", "静音/转场间隙（02:03-02:16无字幕），画面无明显变化"),
    76: ("rejected", "仍在转场后空白段（02:16后才恢复说话），内容未开始"),
    81: ("accepted", "进阶技巧：B-roll插入法，用对应画面替代口播，可照稿念台词"),
    86: ("accepted", "剪辑流程：导入软件后用智能剪口播，自动识别停顿重复"),
    90: ("accepted", "剪辑功能演示：按文字删除实现自动剪辑，高效后期处理"),
    95: ("accepted", "剪辑技巧一：关键帧放大强调重点，在关键词前打关键帧后放大"),
    100: ("accepted", "剪辑技巧二：花字叠加，画面丰富度的第二个小技巧"),
    104: ("accepted", "高级效果：字在人后的制作方法，智能扣像+花字+轨道叠加"),
    109: ("accepted", "片尾效果展示：年度最爱口播效果完整呈现，视频收尾"),
}

unmatched = []
for frame in data['frames']:
    idx = frame['index']
    if idx in frame_evaluations:
        status, reason = frame_evaluations[idx]
        frame['review']['status'] = status
        frame['review']['reason'] = reason
        if status == 'accepted':
            frame['review']['checks'] = {
                'is_clear': True,
                'is_step_relevant': True,
                'has_obstruction': False,
                'needs_replacement': False,
                'needs_annotation': False
            }
        elif status == 'rejected':
            frame['review']['checks'] = {
                'is_clear': True,
                'is_step_relevant': False,
                'has_obstruction': False,
                'needs_replacement': False,
                'needs_annotation': False
            }
    else:
        unmatched.append(idx)

with open(json_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

# Report
for frame in data['frames']:
    print(f"  frame_{frame['index']:05d}  {frame['timestamp']}  {frame['review']['status']:8s}  {frame['review']['reason']}")

accepted = sum(1 for f in data['frames'] if f['review']['status'] == 'accepted')
rejected = sum(1 for f in data['frames'] if f['review']['status'] == 'rejected')
print(f"\nAccepted: {accepted}, Rejected: {rejected}, Total: {len(data['frames'])}")

if unmatched:
    print(f"Warning: {len(unmatched)} frame(s) not in evaluation table, left as pending: {unmatched}", file=sys.stderr)