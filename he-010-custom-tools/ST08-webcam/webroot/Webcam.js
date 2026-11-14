let OGS = {};
const videoElement = document.getElementById('videoElement');
const canvasElement = document.getElementById('canvasElement');
const photoElement = document.getElementById('photoElement');
const captureButton = document.getElementById('captureButton');
const okButton = document.getElementById('okButton');
const nokButton = document.getElementById('nokButton');
const retryButton = document.getElementById('retryButton');
const divVideo = document.getElementById('divVideo');
const divImage = document.getElementById('divImage');

let stream = null;

function updateButtons(capturing) {
    if (capturing) {
        // only show the "capture" button
        captureButton.disabled = false;
        captureButton.style.display = "block";
        okButton.style.display = "none";
        nokButton.style.display = "none";
        retryButton.style.display = "none";
    }
    else {
        // hide the "capture" button and show ok/nok/retry
        captureButton.disabled = true;
        captureButton.style.display = "none";
        okButton.style.display = "block";
        nokButton.style.display = "block";
        retryButton.style.display = "block";
    }
}


async function startWebcam(imgurl) {
    divImage.style.display 		= "none"; 
    divVideo.style.display 		= "block";
    try {
        stream = await navigator.mediaDevices.getUserMedia({ video: true });
        videoElement.srcObject = stream;
        updateButtons(true)
    } catch (error) {
        console.error('Error accessing webcam:', error);
    }
}
async function stopWebcam(imgurl) {
    divImage.style.display 		= "block"; 
    divVideo.style.display 		= "none";
    if (stream) {
        stream.getTracks().forEach(function(track) {
            if (track.readyState == 'live') {
                track.stop();
            }
        }); 
    }
    photoElement.src = imgurl;
    //captureButton.disabled = true;
    updateButtons(false)
}

function btnOkClick() {
    OGS.Emit({ cmd: 'ok-clicked' });
}
function btnNokClick() {
    OGS.Emit({ cmd: 'nok-clicked' });
}
function btnRetryClick() {
    divImage.style.display 		= "none";  // "block"
    divVideo.style.display 		= "block";   // "block"
    updateButtons(true)
}
function capturePhoto() {
    canvasElement.width = videoElement.videoWidth;
    canvasElement.height = videoElement.videoHeight;
    canvasElement.getContext('2d').drawImage(videoElement, 0, 0);
    const photoDataUrl = canvasElement.toDataURL('image/jpeg');
    photoElement.src = photoDataUrl;
    OGS.Emit({ cmd: 'SaveImage', img: photoDataUrl });
    updateButtons(false)
}
captureButton.addEventListener('click', capturePhoto);     
nokButton.addEventListener('click', btnNokClick);
okButton.addEventListener('click', btnOkClick);
retryButton.addEventListener('click', btnRetryClick);



OGS.onInit = function(url) {
	console.log("OGS.onInit called: ", url, OGS);
	//OGS.SendCmd('{ "cmd":"get-version" }');
}
OGS.onShow = function OGS_onShow() {
	console.log("OGS.onShow called!");
    // hide both div's first
    divImage.style.display 		= "none"; // "block"
    divVideo.style.display 		= "none"; // "block"
    OGS.Emit({ cmd: 'OnShow' })
	//RequestParams();
	//OGS.UpdateTimer = setTimeout(OGS.UpdatePositions, 500);
}
OGS.onHide = function() {
	console.log("OGS.onHide called!");
	//clearTimeout(OGS.UpdateTimer);
	//OGS.UpdateTimer = null;
    OGS.Emit({ cmd: 'OnHide' })
}

// interface functions to be called from LUA code
OGS.TriggerWebcam = function(msg) {
	//console.log("OGS.Update() called!", msg);
    let data = JSON.parse(msg)
    // Update the GUI
	console.log("OGS.TriggerWebcam() called!", data);
    if (data.state == 1) {
        // show old image
        stopWebcam(data.imgurl);
    }
    else if (data.state == 2) {
        // capture image
        startWebcam(data.imgurl);
    }
}
OGS.FileSaved = function(msg) {
	//console.log("OGS.Update() called!", msg);
    let data = JSON.parse(msg)
    // Update the GUI
	console.log("OGS.FileSaved() called!", data);
    // Now switch to image view, hide camera (but leave it running)
    photoElement.src = data.imgurl;
    divImage.style.display 		= "block";  // "block"
    divVideo.style.display 		= "none";   // "block"
}

OGS.Emit = function(obj) {
    if (OGS.SendCmd) {
        OGS.SendCmd(JSON.stringify(obj));
    } else {
        console.log('OGS.Send(): ', obj);
        // offline simulation
        if (obj.cmd == 'svg-click') {
            OGS.Update({ nodes: [{name: obj.node, checked: true}] });
        }
    }
}

export {
    OGS
}