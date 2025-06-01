% Clear workspace and figures
clearvars;
close all;

% Create outputs folder if it doesn't exist
outputFolder = 'outputs';
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

% Load the video file
[filename, path] = uigetfile('*.avi');
if isequal(filename, 0)
    disp('No file selected');
    return;
else
    v = VideoReader([path, filename]);
end

fps_original = v.FrameRate;
fps_export = 60;
Vid_dur = v.Duration;
numFrames = round(Vid_dur * fps_original);

% Calibration in micrometers per pixel (based on 2.72 pixels/um ==> 20x)
calibration = 1 / 4.5;  %  4.5 pixel per um (20x_CUHK)

% Read the first frame and select ROI
firstFrame = readFrame(v);
figure; imshow(firstFrame);
title('Draw the Ventricle Region Using Freehand Polygon Tool and Double-Click to Confirm');
ventricleROI = drawfreehand('Closed', true);
wait(ventricleROI);
roiMask = createMask(ventricleROI, firstFrame);

% Initialize area storage
ventricle_areas_pixels = zeros(1, numFrames-1);

% Initialize video writer
outputVideo = VideoWriter(fullfile(outputFolder, 'video_with_area_plot.avi'));
outputVideo.FrameRate = fps_export;
open(outputVideo);

% Set up figure
figureHandle = figure('Position', [100, 100, 1600, 1600]);

% Process video frames
frameIdx = 1;
while hasFrame(v) && frameIdx < numFrames
    frame = readFrame(v);
    grayFrame = rgb2gray(frame);
    roiFrame = grayFrame .* uint8(roiMask);

    bw = imbinarize(roiFrame, 'adaptive');
    bw = imfill(bw, 'holes');
    bw = bwareafilt(bw, 1);

    stats = regionprops(bw, 'Area');
    if ~isempty(stats)
        ventricle_areas_pixels(frameIdx) = stats.Area;
    end

    ventricle_areas_micrometers2 = ventricle_areas_pixels * (calibration^2);
    time_axis = (0:frameIdx-1) / fps_original;

    subplot(2, 1, 1);
    plot(time_axis, ventricle_areas_micrometers2(1:frameIdx), 'b', 'LineWidth', 0.5);
    xlabel('Time (s)'); ylabel('Ventricle Area (\mum^2)');
    title('Ventricle Area Over Time'); grid on;

    subplot(2, 1, 2);
    imshow(frame);
    title(['Frame ', num2str(frameIdx), ' of ', num2str(numFrames)]);
    hold on;
    visboundaries(roiMask, 'Color', 'r', 'LineWidth', 1);
    hold off;

    frameVideo = getframe(figureHandle);
    writeVideo(outputVideo, frameVideo);
    frameIdx = frameIdx + 1;
end

close(outputVideo);

% Post-processing
ventricle_areas_micrometers2 = ventricle_areas_pixels * (calibration^2);
time_axis = (0:numFrames-2) / fps_original;

minPeakProminence = 0.0002 * max(ventricle_areas_micrometers2);
[peaks, locs_peaks] = findpeaks(ventricle_areas_micrometers2, 'MinPeakProminence', minPeakProminence);
[troughs, locs_troughs] = findpeaks(-ventricle_areas_micrometers2, 'MinPeakProminence', minPeakProminence);
troughs = -troughs;

EDA_micrometers2 = mean(peaks);
ESA_micrometers2 = mean(troughs);

V_EDA = EDA_micrometers2^(3/2);
V_ESA = ESA_micrometers2^(3/2);
SV_uL = (V_EDA - V_ESA) * 1e-9;
EF = ((V_EDA - V_ESA) / V_EDA) * 100;

HR = 168.37;
CO = (SV_uL * HR) * 1e6;  % uL/min

disp(['Ejection Fraction (EF): ', num2str(EF, '%.2f'), ' %']);
disp(['Cardiac Output (CO): ', num2str(CO, '%.2f'), ' \muL/min']);

% Final plot
figure;
plot(time_axis, ventricle_areas_micrometers2, 'b', 'LineWidth', 1); hold on;
plot(time_axis(locs_peaks), peaks, 'ro', 'MarkerSize', 10, 'LineWidth', 0.5);
plot(time_axis(locs_troughs), troughs, 'go', 'MarkerSize', 10, 'LineWidth', 0.5);

xlabel('Time (s)'); ylabel('Ventricle Area (\mum^2)');
title('Ventricle Area Over Time with Peaks and Troughs Highlighted'); grid on;

text(0.05, 0.9, ['EF: ', num2str(EF, '%.2f'), ' %'], 'Units', 'normalized', 'FontSize', 12, 'Color', 'r');
text(0.05, 0.85, ['CO: ', num2str(CO, '%.2f'), ' \muL/min'], 'Units', 'normalized', 'FontSize', 12, 'Color', 'r');

saveas(gcf, fullfile(outputFolder, 'Ventricle_Area_Peaks_Troughs_EF_CO.png'));
