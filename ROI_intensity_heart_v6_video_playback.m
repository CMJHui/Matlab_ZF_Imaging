clearvars;
close all;

% Load the video file
[filename, path] = uigetfile('*.mp4');

if isequal(filename, 0)
    disp('No file selected');
    return;
else
    v = VideoReader([path, filename]);
end

fps = v.FrameRate;  % Frames per second
Vid_dur = v.Duration;  % Duration of the video
numFrames = round(Vid_dur * fps);  % Total number of frames

% Check if the number of frames is calculated correctly
fprintf('Total frames: %d\n', numFrames);

% Read the first frame to let the user select the region of interest (ROI)
firstFrame = readFrame(v);
grayFirstFrame = rgb2gray(firstFrame);

% Display the first frame for ROI selection
figure;
imshow(grayFirstFrame);
title('Select the region of interest (heart) and double-click to confirm');
disp('Select the region of interest (heart) using the mouse and double-click to confirm.');

% Use the `drawrectangle` function to allow manual ROI selection with double-click confirmation
roi = drawrectangle;  % ROI selection tool with double-click
wait(roi);  % Wait for the user to double-click to finalize the ROI
roiPosition = round(roi.Position);  % Get the position of the ROI after selection
close;

% Convert ROI position to a mask for applying to the frames
roiMask = poly2mask([roiPosition(1), roiPosition(1)+roiPosition(3), roiPosition(1)+roiPosition(3), roiPosition(1)], ...
                    [roiPosition(2), roiPosition(2), roiPosition(2)+roiPosition(4), roiPosition(2)+roiPosition(4)], ...
                    size(grayFirstFrame, 1), size(grayFirstFrame, 2));

% Reset the VideoReader to the start of the video after reading the first frame
v.CurrentTime = 0;

% Preallocate arrays for pixel intensity calculations
MeanC = zeros(numFrames, 1);  % For storing mean pixel intensities
C_img = zeros(numFrames, 1);  % Will store image data processed per frame

% Loop through each frame of the video
k = 1;  % Frame counter
while hasFrame(v) && k <= numFrames
    % Read the frame
    frame = readFrame(v);
    
    % Convert to grayscale
    grayFrame = rgb2gray(frame);
    
    % Apply contrast adjustment to enhance pixel differences
    enhancedFrame = imadjust(grayFrame);
    
    % Apply the mask to focus on the selected ROI (heart region)
    roiFrame = enhancedFrame .* uint8(roiMask);
    
    % Denoise the frame using a median filter to reduce background noise
    denoisedFrame = medfilt2(roiFrame, [3 3]);  % Adjust filter size if needed
    
    % Calculate the mean pixel intensity of the denoised frame within the ROI
    C_img(k) = mean(denoisedFrame(roiMask));  % Store mean pixel intensity for each frame
    
    k = k + 1;  % Increment the frame counter
end

% If fewer frames were processed than expected, trim the intensity array
if k-1 < numFrames
    MeanC = MeanC(1:k-1);
end

%% Heart Rate Analysis

% Create a time vector
xStart = 0;
dx = 1 / fps;
tt = xStart + (0:k-2) * dx;  % Time vector for each frame

% Calculate the average intensity over time
MeanC = mean(C_img(1:k-1), 2);  % Average intensity across frames

% Plot intensity over time
figure;
plot(tt, MeanC, 'LineWidth', 1);
xlabel('Time (s)');
ylabel('Mean Intensity');
title('Mean Intensity over Time');
saveas(gcf, 'outputs/Mean_Intensity_Over_Time.png');

% Find peaks (heartbeats) to calculate heart rate
[pks, locs] = findpeaks(MeanC, 'MinPeakHeight', 95);  % Adjust 'MinPeakHeight' if needed
num_beats = numel(pks);  % Number of detected heartbeats
DF = num_beats / Vid_dur;  % Dominant frequency (beats per second)
HR = DF * 60;  % Heart rate in beats per minute

% Display the calculated heart rate
disp(['Heart Rate = ', num2str(HR), ' beats per minute']);

% Plot the detected peaks
figure;
plot(tt, MeanC, 'LineWidth', 1); hold on;
plot(tt(locs), pks, 'ro', 'MarkerSize', 8);  % Mark the peaks
xlabel('Time (s)');
ylabel('Mean Intensity');
title(['Heart Rate = ', num2str(HR), ' BPM']);
saveas(gcf, 'outputs/Detected_Heartbeats.png');  % Save the plot with detected peaks

%% Frequency Analysis Using FFT

Cl = MeanC;  % Copy of intensity over time
Ts = mean(diff(tt));  % Sampling interval
Fs = 1 / Ts;  % Sampling frequency
Fn = Fs / 2;  % Nyquist frequency
L = numel(tt);  % Signal length
Clm = Cl - mean(Cl);  % Remove the DC component (mean)
FCl = fft(Clm) / L;  % Perform FFT and normalize
Fv = linspace(0, 1, fix(L / 2) + 1) * Fn;  % Frequency vector
Iv = 1:numel(Fv);  % Index vector

% Plot the power spectrum
figure;
plot(Fv, abs(FCl(Iv)).^2, 'LineWidth', 1);  % Power spectrum
xlabel('Frequency (Hz)');
ylabel('Power');
title('Power Spectrum of Heart Rate Signal');
xlim([0 5]);  % Limit to a reasonable frequency range (e.g., 0-5 Hz)
saveas(gcf, 'outputs/Power_Spectrum.png');  % Save the plot

% Find peaks in the frequency spectrum to determine dominant frequency
[fft_peaks, fft_locs] = findpeaks(abs(FCl(Iv)).^2, 'MinPeakHeight', 0.1);

% Check if any peaks were found
if ~isempty(fft_locs)
    dominant_frequency = Fv(fft_locs(1));  % First peak is the dominant frequency

    % Convert dominant frequency to heart rate in BPM
    heart_rate_fft = dominant_frequency * 60;
    disp(['Estimated Heart Rate (FFT) = ', num2str(heart_rate_fft), ' BPM']);
else
    % If no peaks are found, display a warning
    disp('No peaks found in the FFT. Unable to determine dominant frequency.');
    heart_rate_fft = NaN;  % Assign NaN (Not a Number) to indicate no valid result
end

%% Export Video with Mean Intensity Plot

% Function to export video with plot
outputVideo = VideoWriter('outputs/Heart_Rate_With_Intensity_Plot.avi');
outputVideo.FrameRate = fps;
open(outputVideo);

figure;
for i = 1:k-1
    % Read original frame
    v.CurrentTime = (i-1) / fps;
    frame = readFrame(v);
    
    % Plot intensity up to the current frame
    subplot(2, 1, 1);
    plot(tt(1:i), MeanC(1:i), 'LineWidth', 1);
    xlabel('Time (s)');
    ylabel('Mean Intensity');
    title('Mean Intensity over Time');
    xlim([0 tt(end)]);
    ylim([min(MeanC), max(MeanC)]);
    
    % Display the original video frame
    subplot(2, 1, 2);
    imshow(frame);
    title('Video Frame');
    
    % Capture the figure as a frame for the video
    frameWithPlot = getframe(gcf);
    writeVideo(outputVideo, frameWithPlot);
end

close(outputVideo);
disp('Video with intensity plot exported successfully.');

