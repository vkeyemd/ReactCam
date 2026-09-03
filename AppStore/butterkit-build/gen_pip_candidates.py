import json, sys, time, uuid, urllib.request, urllib.parse, os
EP="http://gaviai:8188"
OUT=sys.argv[1]
W,H=720,1280
STYLE_2D="hand-drawn storybook illustration, clean ink outlines, soft watercolor shading, gentle pastel colors, whimsical children's book art"
STYLE_3D="3D rendered, pixar style, soft studio lighting, fluffy fur, big shiny eyes"
CANDS=[
 ("a-plush-gasp", f"A cute pink plush bunny toy with stitched seams and button eyes sitting on a grey sofa in a cozy living room, facing the camera like a phone selfie, eyes wide with wonder and mouth open in a delighted gasp, {STYLE_2D}"),
 ("b-plush-laugh", f"A cute patchwork plush bunny with floppy ears sitting on a couch, front-facing phone camera view, laughing with pure joy, paws raised, eyes squeezed shut in a huge smile, cozy living room with a lamp behind, {STYLE_2D}"),
 ("c-3d-surprised", f"A cute fluffy white baby bunny wearing a striped t-shirt sitting on a couch at home, looking straight into a front-facing phone camera, mouth open in a surprised delighted expression, cozy living room, warm lamp light, {STYLE_3D}"),
 ("d-3d-laugh", f"A cute fluffy grey baby bunny in a yellow hoodie on a couch, front-facing selfie camera angle, laughing hard with a big open smile and sparkling eyes, hands on cheeks, cozy living room background, {STYLE_3D}"),
]
def wf(prompt, seed):
    return {
     "1":{"inputs":{"unet_name":"z_image_turbo_bf16.safetensors","weight_dtype":"fp8_e4m3fn"},"class_type":"UNETLoader"},
     "2":{"inputs":{"images":["9",0],"filename_prefix":"reactcam/pip"},"class_type":"SaveImage"},
     "3":{"inputs":{"text":prompt,"clip":["4",0]},"class_type":"CLIPTextEncode"},
     "4":{"inputs":{"clip_name":"qwen_3_4b.safetensors","type":"lumina2","device":"default"},"class_type":"CLIPLoader"},
     "5":{"inputs":{"seed":seed,"steps":9,"cfg":1,"sampler_name":"res_multistep","scheduler":"simple","denoise":1,"model":["1",0],"positive":["3",0],"negative":["10",0],"latent_image":["12",0]},"class_type":"KSampler"},
     "9":{"inputs":{"samples":["5",0],"vae":["11",0]},"class_type":"VAEDecode"},
     "10":{"inputs":{"conditioning":["3",0]},"class_type":"ConditioningZeroOut"},
     "11":{"inputs":{"vae_name":"ae.safetensors"},"class_type":"VAELoader"},
     "12":{"inputs":{"width":W,"height":H,"batch_size":1},"class_type":"EmptySD3LatentImage"},
    }
def post(path, data):
    req=urllib.request.Request(EP+path, data=json.dumps(data).encode(), headers={"Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(req, timeout=60))
def get(path):
    return urllib.request.urlopen(EP+path, timeout=60).read()
cid=str(uuid.uuid4())
for name,prompt in CANDS:
    seed=int.from_bytes(os.urandom(6),"big")
    t0=time.time()
    r=post("/prompt",{"prompt":wf(prompt,seed),"client_id":cid})
    pid=r["prompt_id"]
    while True:
        h=json.loads(get(f"/history/{pid}"))
        if pid in h:
            st=h[pid].get("status",{})
            if st.get("status_str")=="error":
                print(name,"ERROR",json.dumps(st)[:800]); break
            outs=h[pid]["outputs"]
            img=[im for o in outs.values() for im in o.get("images",[])][0]
            q=urllib.parse.urlencode({"filename":img["filename"],"subfolder":img.get("subfolder",""),"type":img.get("type","output")})
            data=get("/view?"+q)
            p=f"{OUT}/{name}.png"; open(p,"wb").write(data)
            print(f"{name}: {len(data)//1024} KB in {time.time()-t0:.1f}s seed={seed}")
            break
        if time.time()-t0>240: print(name,"TIMEOUT"); break
        time.sleep(1.5)
