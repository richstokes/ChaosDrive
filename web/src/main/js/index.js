import wasm from './genplus.js';
import './genplus.wasm';

const CANVAS_WIDTH = 640;
const CANVAS_HEIGHT = 480;
const SOUND_FREQUENCY = 44100;
const SAMPLING_PER_FPS = 736;
const GAMEPAD_API_INDEX = 32;

// emulator
let gens;
let romdata;
let vram;
let input;
let initialized = false;
let pause = false;

// canvas member
let canvas;
let canvasContext;
let canvasImageData;

// fps control
const FPS = 60;
const INTERVAL = 1000 / FPS;
let now;
let then;
let delta;
let startTime;
let fps;
let frame;

// audio member
const SOUND_DELAY_FRAME = 8;
let audioContext;
let audio_l;
let audio_r;
let soundShedTime = 0;
let soundDelayTime = SAMPLING_PER_FPS * SOUND_DELAY_FRAME / SOUND_FREQUENCY;

// for iOS
let isSafari = false;

// keyboard state
const keys = new Set();
const prevKeys = new Set(); // for single-press detection

// ChaosDrive status message
let chaosMessage = '';
let chaosMessageTimer = 0;
function showChaosMessage(msg) {
    chaosMessage = msg;
    chaosMessageTimer = 120; // ~2 seconds at 60fps
}

document.addEventListener('keydown', function(e) {
    keys.add(e.code);
    // prevent arrow keys / tab from scrolling
    if(['ArrowUp','ArrowDown','ArrowLeft','ArrowRight','Tab'].includes(e.code)) {
        e.preventDefault();
    }
    // Prevent default for chaos keys too
    if(['BracketLeft','BracketRight','Backslash','Slash','Semicolon',
        'Comma','Period'].includes(e.code)) {
        e.preventDefault();
    }
    if(e.code === 'KeyZ') {
        pause = !pause;
    }
    if(e.code === 'Tab' && gens) {
        gens._start();
    }
});
document.addEventListener('keyup', function(e) {
    keys.delete(e.code);
});

const message = function(mes) {
    canvasContext.clearRect(0, 0, canvas.width, canvas.height);
    canvasContext.font = "24px monospace";
    canvasContext.fillStyle = "#fff";
    canvasContext.fillText(mes, 250, 250);
    canvasContext.font = "12px monospace";
    canvasContext.fillStyle = "#0f0";
};

const initAudio = function() {
    if(audioContext) return;
    audioContext = new (window.AudioContext || window.webkitAudioContext)({
        sampleRate: SOUND_FREQUENCY
    });
    // iOS dummy audio to unlock audio context
    let audioBuffer = audioContext.createBuffer(2, SAMPLING_PER_FPS, SOUND_FREQUENCY);
    let dummy = new Float32Array(SAMPLING_PER_FPS);
    dummy.fill(0);
    audioBuffer.getChannelData(0).set(dummy);
    audioBuffer.getChannelData(1).set(dummy);
    sound(audioBuffer);
};

const loadRom = function(bytes) {
    romdata = new Uint8Array(gens.HEAPU8.buffer, gens._get_rom_buffer_ref(bytes.byteLength), bytes.byteLength);
    romdata.set(new Uint8Array(bytes));
    canvas.style.display = 'block';
    initialized = true;
    // init audio (user gesture from file picker satisfies browser policy)
    initAudio();
    // start immediately
    start();
};

// canvas setting
(function() {
    canvas = document.getElementById('screen');
    canvas.setAttribute('width', CANVAS_WIDTH);
    canvas.setAttribute('height', CANVAS_HEIGHT);
    let pixelRatio = window.devicePixelRatio ? window.devicePixelRatio : 1;
    if(pixelRatio > 1 && window.screen.width < CANVAS_WIDTH) {
        canvas.style.width = CANVAS_WIDTH + "px";
        canvas.style.height = CANVAS_HEIGHT + "px";
    }
    canvasContext = canvas.getContext('2d');
    canvasImageData = canvasContext.createImageData(CANVAS_WIDTH, CANVAS_HEIGHT);
    // for fps print
    fps = 0;
    frame = FPS;
    startTime = new Date().getTime();
})();

// init wasm module
wasm().then(function(module) {
    gens = module;
    gens._init();
    console.log(gens);
    // listen for ROM file selection
    document.getElementById('rom-file').addEventListener('change', function(e) {
        let file = e.target.files[0];
        if(!file) return;
        let reader = new FileReader();
        reader.onload = function() {
            document.getElementById('rom-picker').style.display = 'none';
            loadRom(reader.result);
        };
        reader.readAsArrayBuffer(file);
    });
});

const start = function() {
    if(!initialized) return;
    canvasContext.clearRect(0, 0, canvas.width, canvas.height);
    // emulator start
    gens._start();
    // vram view
    vram = new Uint8ClampedArray(gens.HEAPU8.buffer, gens._get_frame_buffer_ref(), CANVAS_WIDTH * CANVAS_HEIGHT * 4);
    // audio view
    audio_l = new Float32Array(gens.HEAPF32.buffer, gens._get_web_audio_l_ref(), SAMPLING_PER_FPS);
    audio_r = new Float32Array(gens.HEAPF32.buffer, gens._get_web_audio_r_ref(), SAMPLING_PER_FPS);
    // input
    input = new Float32Array(gens.HEAPF32.buffer, gens._get_input_buffer_ref(), GAMEPAD_API_INDEX);
    // iOS
    let ua = navigator.userAgent
    if(ua.match(/Safari/) && !ua.match(/Chrome/) && !ua.match(/Edge/)) {
        isSafari = true;
    }
    // game loop
    then = Date.now();
    loop();
};

const keyscan = function() {
    input.fill(0);
    // gamepad
    let gamepads = navigator.getGamepads();
    if(gamepads.length > 0) {
        let gamepad = gamepads[0];
        if(gamepad != null) {
            if(isSafari) {
                input[7] = gamepad.axes[5] * -1;
                input[6] = gamepad.axes[4];
            } else if(gamepad.id.match(/Microsoft/)) {
                gamepad.axes.forEach((value, index) => {
                    input[index] = value;
                });
            } else {
                input[7] = gamepad.axes[1];
                input[6] = gamepad.axes[0];
            }
            gamepad.buttons.forEach((button, index) => {
                input[index + 8] = button.value;
            });
        }
    }
    // keyboard
    // D-Pad: arrow keys
    if(keys.has('ArrowUp'))    input[7] = -1;
    if(keys.has('ArrowDown'))  input[7] = 1;
    if(keys.has('ArrowLeft'))  input[6] = -1;
    if(keys.has('ArrowRight')) input[6] = 1;
    // A, B, C
    if(keys.has('KeyA')) input[8 + 2] = 1; // A
    if(keys.has('KeyS')) input[8 + 3] = 1; // B
    if(keys.has('KeyD')) input[8 + 1] = 1; // C
    // START
    if(keys.has('Enter')) input[8 + 7] = 1;
};

const sound = function(audioBuffer) {
    let source = audioContext.createBufferSource();
    source.buffer = audioBuffer;
    source.connect(audioContext.destination);
    let currentSoundTime = audioContext.currentTime;
    if(currentSoundTime < soundShedTime) {
        source.start(soundShedTime);
        soundShedTime += audioBuffer.duration;
    } else {
        source.start(currentSoundTime);
        soundShedTime = currentSoundTime + audioBuffer.duration + soundDelayTime;
    }
};

// ChaosDrive: process chaos key bindings each frame
const chaosScan = function() {
    if(!gens) return;

    // --- VRAM manipulation (hold-to-repeat) ---
    if(keys.has('KeyO'))         { gens._chaos_shift_vram_up();          showChaosMessage('VRAM shifted up'); }
    if(keys.has('KeyL'))         { gens._chaos_shift_vram_down();        showChaosMessage('VRAM shifted down'); }
    if(keys.has('KeyK'))         { gens._chaos_shift_vram_left();        showChaosMessage('VRAM shifted left'); }
    if(keys.has('Semicolon'))    { gens._chaos_shift_vram_right();       showChaosMessage('VRAM shifted right'); }
    if(keys.has('KeyI'))         { gens._chaos_shift_vram_down_random(); showChaosMessage('VRAM shifted random'); }
    if(keys.has('KeyP'))         { gens._chaos_corrupt_vram_one_byte();  showChaosMessage('VRAM corrupted (1 byte)'); }

    // --- VRAM invert (single press) ---
    if(keys.has('Backslash') && !prevKeys.has('Backslash')) {
        gens._chaos_invert_vram_contents(); showChaosMessage('VRAM inverted');
    }

    // --- CRAM (hold-to-repeat for [ and ]) ---
    if(keys.has('BracketLeft'))  { gens._chaos_randomize_cram();  showChaosMessage('CRAM randomized'); }
    if(keys.has('BracketRight')) { gens._chaos_shift_cram_up();   showChaosMessage('CRAM shifted up'); }

    // --- CRAM persistent corruption (single press) ---
    if(keys.has('KeyY') && !prevKeys.has('KeyY')) {
        gens._chaos_enable_cram_corruption(); showChaosMessage('CRAM corruption ON');
    }
    if(keys.has('KeyU') && !prevKeys.has('KeyU')) {
        gens._chaos_disable_cram_corruption(); showChaosMessage('CRAM corruption OFF');
    }

    // --- Sprite/Scroll (single press) ---
    if(keys.has('KeyR') && !prevKeys.has('KeyR')) {
        gens._chaos_scroll_register_fuzzing(); showChaosMessage('Scroll registers fuzzed');
    }
    if(keys.has('KeyT') && !prevKeys.has('KeyT')) {
        gens._chaos_sprite_attribute_scramble(); showChaosMessage('Sprite attributes scrambled');
    }

    // --- Audio (single press for X, C; hold for V, B, N) ---
    if(keys.has('KeyX') && !prevKeys.has('KeyX')) {
        gens._chaos_enable_fm_corruption(); showChaosMessage('FM corruption ON');
    }
    if(keys.has('KeyC') && !prevKeys.has('KeyC')) {
        gens._chaos_disable_fm_corruption(); showChaosMessage('FM corruption OFF');
    }
    if(keys.has('KeyV'))         { gens._chaos_corrupt_dac_data();       showChaosMessage('DAC data corrupted'); }
    if(keys.has('KeyB'))         { gens._chaos_bitcrush_audio_memory();  showChaosMessage('Audio bitcrushed'); }
    if(keys.has('KeyN'))         { gens._chaos_detune_fm_registers();    showChaosMessage('FM detuned'); }

    // --- Audio memory shift (single press) ---
    if(keys.has('Comma') && !prevKeys.has('Comma')) {
        gens._chaos_shift_audio_memory_up(); showChaosMessage('Audio memory shifted up');
    }
    if(keys.has('Period') && !prevKeys.has('Period')) {
        gens._chaos_shift_audio_memory_down(); showChaosMessage('Audio memory shifted down');
    }

    // --- General mayhem (F, G hold; H, J, / single press) ---
    if(keys.has('KeyF'))         { gens._chaos_corrupt_68k_ram_one_byte(); showChaosMessage('68K RAM corrupted'); }
    if(keys.has('KeyG'))         { gens._chaos_critical_ram_scramble();    showChaosMessage('Critical RAM scrambled'); }
    if(keys.has('KeyH') && !prevKeys.has('KeyH')) {
        gens._chaos_program_counter_increment(); showChaosMessage('PC incremented');
    }
    if(keys.has('KeyJ') && !prevKeys.has('KeyJ')) {
        gens._chaos_random_register_corruption(); showChaosMessage('Register corrupted');
    }
    if(keys.has('Slash') && !prevKeys.has('Slash')) {
        gens._chaos_flip_game_logic_variables(); showChaosMessage('Game variables flipped');
    }

    // Update previous key state
    prevKeys.clear();
    for(const k of keys) prevKeys.add(k);
};

const loop = function() {
    requestAnimationFrame(loop);
    now = Date.now();
    delta = now - then;
    if (delta > INTERVAL && !pause) {
        keyscan();
        chaosScan();
        // update
        gens._tick();
        then = now - (delta % INTERVAL);
        // draw
        canvasImageData.data.set(vram);
        canvasContext.putImageData(canvasImageData, 0, 0);
        // fps
        frame++;
        if(new Date().getTime() - startTime >= 1000) {
            fps = frame;
            frame = 0;
            startTime = new Date().getTime();
        }
        // sound
        gens._sound();
        // sound hack
        if(fps < FPS) {
            soundShedTime = 0;
        } else {
            let audioBuffer = audioContext.createBuffer(2, SAMPLING_PER_FPS, SOUND_FREQUENCY);
            audioBuffer.getChannelData(0).set(audio_l);
            audioBuffer.getChannelData(1).set(audio_r);
            sound(audioBuffer);
        }
        // ChaosDrive status + FPS
        canvasContext.font = "12px monospace";
        canvasContext.fillStyle = "#0f0";
        canvasContext.fillText("FPS " + fps, 0, 480 - 16);
        if(chaosMessageTimer > 0) {
            canvasContext.fillStyle = "#ff0";
            canvasContext.fillText(chaosMessage, 0, 480 - 32);
            chaosMessageTimer--;
        }
    }
};
