"""Verify the actual optimized AAB retains the sealed ride alarm audio."""
from pathlib import Path
import sys,hashlib,zipfile,json
root=Path(__file__).parent
source=root/'source'
if not source.exists():source=root/'driver-source'
aab=Path(sys.argv[1])
expected=(source/'android/app/src/main/res/raw/fluxidi_ride_chime.wav').read_bytes()
digest=hashlib.sha256(expected).hexdigest()
with zipfile.ZipFile(aab) as bundle:
 matches=[i.filename for i in bundle.infolist() if i.file_size==len(expected) and hashlib.sha256(bundle.read(i.filename)).hexdigest()==digest]
 assert len(matches)==1,('RELEASE_ALARM_AUDIO_MISSING_OR_CHANGED',matches)
print(json.dumps({'pass':True,'audioPath':matches[0],'audioSha256':digest,'audioBytes':len(expected)}))
