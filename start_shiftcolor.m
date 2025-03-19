function [rec, status, exception] = start_shiftcolor(opts)
arguments
    opts.SkipSyncTests (1, 1) {mustBeNumericOrLogical} = false
end

% ---- configure exception ----
status = 0;
exception = [];

% ---- configure sequence ----
config = readtable(fullfile("MateShiftColor", "prac.xlsx"));
rec = config;
rec.onset_real = nan(height(config), 1);
rec.resp_raw = cell(height(config), 1);
rec.resp = cell(height(config), 1);
rec.rt = nan(height(config), 1);
timing = struct( ...
    'iti', 0.5, ... % inter-trial-interval
    'tdur', 2.5); % trial duration
p.color = [1 0 0; 0 1 0] * 255; % red / green
p.sz = 200; %size
cuetxt = ['X' 'Y']; %'X':shape task,'Y':color task

% ---- configure screen and window ----
% setup default level of 2
PsychDefaultSetup(2);
% screen selection
screen_to_display = max(Screen('Screens'));
% set the start up screen to black
old_visdb = Screen('Preference', 'VisualDebugLevel', 1);
% do not skip synchronization test to make sure timing is accurate
old_sync = Screen('Preference', 'SkipSyncTests', double(opts.SkipSyncTests));
% use FTGL text plugin
old_text_render = Screen('Preference', 'TextRenderer', 1);
% set priority to the top
old_pri = Priority(MaxPriority(screen_to_display));
% PsychDebugWindowConfiguration([], 0.1);

% ---- keyboard settings ----
KbName('UnifyKeyNames')
keys = struct( ...
    'start', KbName('s'), ...
    'exit', KbName('Escape'), ...
    'left', KbName('1!'), ...
    'right', KbName('4$'));

% ---- stimuli presentation ----
% the flag to determine if the experiment should exit early
early_exit = false;

try
     % open a window and set its background color as black
    [window_ptr, window_rect] = PsychImaging('OpenWindow', ...
        screen_to_display, BlackIndex(screen_to_display));
    % disable character input and hide mouse cursor
    ListenChar(2);
    HideCursor;
    % set blending function
    Screen('BlendFunction', window_ptr, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    % set default font name
    Screen('TextFont', window_ptr, 'SimHei');
    Screen('TextSize', window_ptr, round(0.06 * RectHeight(window_rect)));
    % get inter flip interval
    ifi = Screen('GetFlipInterval', window_ptr);

    % configure shape location
    r = CenterRect([0 0 1 1]*p.sz, window_rect);
    circle = CenterRect([0 0 1 1]*p.sz*0.8, window_rect);
    triagl = [mean(r([1 3])) r(2)+p.sz*0.1;
          r(1)+p.sz*0.1  r(4)-p.sz*0.1;
          r(3)-p.sz*0.1  r(4)-p.sz*0.1];

    % display welcome/instr screen and wait for a press of 's' to start
    sq=imread('MateShiftColor\semang1.jpg');
    tex=Screen('MakeTexture',window_ptr,sq);
    Screen('DrawTexture',window_ptr,tex);
    Screen('Flip',window_ptr); 
    [ keyIsDown, ~, keyCode ] = KbCheck;
    keyCode = find(keyCode, 1);
    if keyIsDown
        ignoreKey=keyCode;
        DisableKeysForKbCheck(ignoreKey);
    end
    while ~early_exit
        % here we should detect for a key press and release
        [resp_timestamp, key_code] = KbStrokeWait(-1);
        if key_code(keys.start)
            % start_time = resp_timestamp;
            break
        elseif key_code(keys.exit)
            early_exit = true;
        end
    end
    str = sprintf(['请根据提示对颜色或形状进行判断\n' ...
            '红色或者圆圈按%s\n绿色或者三角形按%s\n' ...
            '请又快又准确的进行判断\n' ...
            '接下来是正式实验，不会有提示了\n' ...
            '按s键开始'], '1','4');
    Screen('TextSize', window_ptr, 36);
    DrawFormattedText(window_ptr, double(str), 'center', 'center', ...
        WhiteIndex(window_ptr), [], 0, 0, 2);
    Screen('Flip', window_ptr);
    while ~early_exit
        % here we should detect for a key press and release
        [resp_timestamp, key_code] = KbStrokeWait(-1);
        if key_code(keys.start)
            start_time = resp_timestamp;
            break
        elseif key_code(keys.exit)
            early_exit = true;
        end
    end

    % main experiment
    for trial_order = 1:height(config)
        if early_exit
            break
        end
        this_trial = config(trial_order, :);
        % stim_str = [num2str(this_trial.shape), '    ', this_trial.color{:}];
        r = CenterRect([0 0 1 1]*p.sz, window_rect); 

        % initialize responses
        resp_made = false;
        resp_code = nan;

        % initialize stimulus timestamps
        stim_onset = start_time + this_trial.onset;
        stim_offset = stim_onset + timing.tdur;
        trial_end = stim_offset + timing.iti;
        onset_timestamp = nan;
        offset_timestamp = nan;

        % now present stimuli and check user's response
        while ~early_exit
            [key_pressed, timestamp, key_code] = KbCheck(-1);
            if key_code(keys.exit)
                early_exit = true;
                break
            end
            if key_pressed
                if ~resp_made
                    resp_code = key_code;
                    resp_timestamp = timestamp;
                end
                resp_made = true;
            end
            if timestamp > trial_end - 0.5 * ifi
                % remaining time is not enough for a new flip
                break
            end
            if timestamp < stim_onset || timestamp >= stim_offset
                vbl = Screen('Flip', window_ptr);
                if timestamp >= stim_offset && isnan(offset_timestamp)
                    offset_timestamp = vbl;
                end
            elseif timestamp < stim_offset - 0.5 * ifi
                Screen('TextSize', window_ptr, 72);
                DrawFormattedText(window_ptr, cuetxt(this_trial.task), 'center', r(2)-100, ...
                    WhiteIndex(window_ptr));
                vbl = Screen('Flip', window_ptr, [], 1);
                if this_trial.shape == 1
                    Screen('FrameOval', window_ptr, p.color(this_trial.color,:), circle, 4);
                else
                    Screen('FramePoly', window_ptr, p.color(this_trial.color,:), triagl, 4);
                end
                
                if isnan(onset_timestamp)
                    onset_timestamp = vbl;
                end
                
            end       
        end
        % analyze user's response
        if ~resp_made
            resp_raw = '';
            resp = '';
            rt = 0;
        else
            resp_raw = string(strjoin(cellstr(KbName(resp_code)), '|'));
            valid_names = {'left', 'right'};
            valid_codes = cellfun(@(x) keys.(x), valid_names);
            if sum(resp_code) > 1 || (~any(resp_code(valid_codes)))
                resp = 'invalid';
            else
                resp = valid_names{valid_codes == find(resp_code)};
            end
            rt = resp_timestamp - onset_timestamp;
        end
        rec.onset_real(trial_order) = onset_timestamp;
        rec.resp_raw{trial_order} = resp_raw;
        rec.resp{trial_order} = resp;
        rec.rt(trial_order) = rt;
    end
catch exception
    status = -1;
end

% --- post presentation jobs
Screen('Close');
sca;
% enable character input and show mouse cursor
ListenChar;
ShowCursor;

% ---- restore preferences ----
Screen('Preference', 'VisualDebugLevel', old_visdb);
Screen('Preference', 'SkipSyncTests', old_sync);
Screen('Preference', 'TextRenderer', old_text_render);
Priority(old_pri);

if ~isempty(exception)
    rethrow(exception)
end
end