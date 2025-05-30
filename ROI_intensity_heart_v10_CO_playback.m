%% Heart Rate, Ejection Fraction, and Cardiac Output Estimation with Combined Video and Area Plot

clearvars;
close all;

% Create outputs folder if it doesn't exist
outputFolder = 'outputs';
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

% Load the video file
[filename, path] = uigetfile('*.mp4');
if isequal(filename, 0)
    disp('No file selected');
    return;
else
    v = VideoReader([path, filename]);
end

fps_original = v.FrameRate;  % Original frames per second of the video
fps_export = 60;  % Desired export frame rate
Vid_dur = v.Duration;  % Duration of the video
numFrames = round(Vid_dur * fps_original);  % Total number of frames

% Calibration factor in micrometers per pixel
calibration = 7.3;  % 0.43 micrometers per pixel

% Read the first frame and select ROI (ventricle) using freehand polygon
firstFrame = readFrame(v);
figure; imshow(firstFrame);
title('Draw the Ventricle Region Using Freehand Polygon Tool and Double-Click to Confirm');
ventricleROI = drawfreehand('Closed', true);  % Freehand tool for ROI
wait(ventricleROI);  % Wait for the user to double-click and confirm

% Extract the mask from the freehand ROI
roiMask = createMask(ventricleROI, firstFrame);

% Initialize storage for areas
ventricle_areas_pixels = zeros(1, numFrames-1);  % Exclude the last frame

% Initialize video writer for saving the timelapse video with the area plot at 60 fps
outputVideo = VideoWriter(fullfile(outputFolder, 'video_with_area_plot.avi'));
outputVideo.FrameRate = fps_export;
open(outputVideo);

% Prepare the figure for plotting
figureHandle = figure('Position', [100, 100, 1600, 1600]);  % Set video dimension to 1600x1600

% Loop through the video and calculate ventricle area for each frame, excluding the last frame
frameIdx = 1;
while hasFrame(v) && frameIdx < numFrames
    frame = readFrame(v);
    grayFrame = rgb2gray(frame);
    
    % Apply the ROI mask to the current frame
    roiFrame = grayFrame .* uint8(roiMask);  % Mask the region of interest
    
    % Threshold and segment the ventricle
    bw = imbinarize(roiFrame, 'adaptive');  % Adaptive thresholding
    bw = imfill(bw, 'holes');               % Fill holes
    bw = bwareafilt(bw, 1);                 % Keep largest object (ventricle)
    
    % Calculate the ventricle area (in pixels)
    stats = regionprops(bw, 'Area');
    if ~isempty(stats)
        ventricle_areas_pixels(frameIdx) = stats.Area;
    end
    
    % Convert ventricle area from pixels to micrometers²
    ventricle_areas_micrometers2 = (ventricle_areas_pixels * (calibration^2))/1e6;
    
    % Time axis for the plot
    time_axis = (0:frameIdx-1) / fps_original;
    
    % Plot the ventricle area over time on the left side of the figure
    subplot(2, 1, 1);  % 1 row, 2 columns, 1st plot
    plot(time_axis, ventricle_areas_micrometers2(1:frameIdx), 'b', 'LineWidth', 0.5);
    xlabel('Time (s)');
    ylabel('Ventricle Area (\mum^2)');
    title('Ventricle Area Over Time');
    grid on;
    
    % Show the video frame with ROI on the right side of the figure
    subplot(2, 1, 2);  % 1 row, 2 columns, 2nd plot
    imshow(frame);  % Display the current video frame
    title(['Frame ', num2str(frameIdx), ' of ', num2str(numFrames)]);
    hold on;
    visboundaries(roiMask, 'Color', 'r', 'LineWidth', 1);  % Overlay the ROI mask
    hold off;
    
    % Capture the current figure as a frame in the output video
    frameVideo = getframe(figureHandle);
    writeVideo(outputVideo, frameVideo);
    
    frameIdx = frameIdx + 1;
end

% Close the video writer
close(outputVideo);

% Post-processing for Ejection Fraction and Cardiac Output

% Convert the areas from pixels to micrometers²
ventricle_areas_micrometers2 = (ventricle_areas_pixels * (calibration^2))/1e6;

% Time axis for the plot
time_axis = (0:numFrames-2) / fps_original;  % Exclude the last frame

% Set onset and offset threshold to eliminate small peaks and troughs (noise)
minPeakProminence = 0.001 * max(ventricle_areas_micrometers2);  % 1% of the maximum area as the threshold

% Find all peaks (for EDA) and all troughs (for ESA)
[peaks, locs_peaks] = findpeaks(ventricle_areas_micrometers2, 'MinPeakProminence', minPeakProminence);
[troughs, locs_troughs] = findpeaks(-ventricle_areas_micrometers2, 'MinPeakProminence', minPeakProminence);
troughs = -troughs;  % Negate to convert back to positive values

% Average the peaks and troughs for EDA and ESA calculation
EDA_micrometers2 = mean(peaks);
ESA_micrometers2 = mean(troughs);

% Stroke Volume (SV) and Ejection Fraction (EF) calculation
SV_uL = (EDA_micrometers2^(3/2) - ESA_micrometers2^(3/2)) / 1e9;  % SV in uL
EF = (SV_uL / (EDA_micrometers2^(3/2) / 1e9)) * 100;

% Heart Rate (HR) estimation (replace with actual HR)
HR = 152.4;  % Use a real HR value from other analysis if available

% Cardiac Output (CO) calculation
CO = (SV_uL * HR) * 1e9;

% Display EF and CO values
disp(['Ejection Fraction (EF): ', num2str(EF, '%.2f'), ' %']);
disp(['Cardiac Output (CO): ', num2str(CO, '%.2f'), ' \muL/min']);

% Generate and save the final figure for ventricle area with peaks and troughs

figure;
plot(time_axis, ventricle_areas_micrometers2, 'b', 'LineWidth', 2); hold on;
plot(time_axis(locs_peaks), peaks, 'ro', 'MarkerSize', 10, 'LineWidth', 1);  % Peaks for EDA
plot(time_axis(locs_troughs), troughs, 'go', 'MarkerSize', 10, 'LineWidth', 1);  % Troughs for ESA
xlabel('Time (s)');
ylabel('Ventricle Area (\mum^2)');
title('Ventricle Area Over Time with Peaks and Troughs Highlighted');
grid on;

% Add text annotations for EF and CO
text(0.05, 0.9, ['EF: ', num2str(EF, '%.2f'), ' %'], 'Units', 'normalized', 'FontSize', 12, 'Color', 'r');
text(0.05, 0.85, ['CO: ', num2str(CO, '%.2f'), ' \muL/min'], 'Units', 'normalized', 'FontSize', 12, 'Color', 'r');

% Save the figure with peaks, troughs, and EF/CO values
saveas(gcf, fullfile(outputFolder, 'Ventricle_Area_Peaks_Troughs_EF_CO.png'));
