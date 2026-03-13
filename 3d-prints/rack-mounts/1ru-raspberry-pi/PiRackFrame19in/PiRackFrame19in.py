#Author: Home Ops
#Description: 19" 1RU Rack Mount Frame for Raspberry Pi - Based on uktricky's 10" design
#
# This is a 19" adaptation of the modular 10" homelab rack design.
# Open frame construction with corner gussets for rigidity.
# Fits 4 Raspberry Pis (vs 2 in the 10" version)

import adsk.core, adsk.fusion, adsk.cam, traceback
import math

def run(context):
    ui = None
    try:
        app = adsk.core.Application.get()
        ui = app.userInterface
        design = app.activeProduct
        rootComp = design.rootComponent

        # Create new component for the rack
        occurrences = rootComp.occurrences
        newComp = occurrences.addNewComponent(adsk.core.Matrix3D.create())
        rackComp = newComp.component
        rackComp.name = "19in_1U_Pi_Rack_Frame"

        # ============ PARAMETERS ============
        # All dimensions in cm (Fusion default)

        # 19" Rack standards
        rack_width = 48.26          # 482.6mm - 19" standard
        rack_height = 4.445         # 44.45mm - 1U standard
        ear_width = 1.5875          # 15.875mm - standard ear

        # Frame dimensions
        frame_thickness = 0.5       # 5mm thick frame members
        frame_depth = 12.0          # 120mm depth (adjust as needed)

        # Bay configuration (4 bays for 4 Pis)
        num_bays = 4

        # Gusset/corner bracket dimensions
        gusset_size = 1.5           # 15mm gusset legs
        gusset_thickness = 0.5      # 5mm thick

        # Mounting holes
        rack_hole_diameter = 0.65   # 6.5mm for M6/#10-32
        rack_hole_offset_y = 0.8    # Offset from front edge
        rack_hole_spacing_z = 1.5875  # Vertical spacing between holes

        # Calculated values
        inner_width = rack_width - (2 * ear_width)
        bay_width = inner_width / num_bays
        center_x = rack_width / 2

        # ============ SKETCHES & FEATURES ============
        sketches = rootComp.sketches
        xyPlane = rootComp.xYConstructionPlane
        xzPlane = rootComp.xZConstructionPlane
        yzPlane = rootComp.yZConstructionPlane
        extrudes = rootComp.features.extrudeFeatures
        fillets = rootComp.features.filletFeatures
        chamfers = rootComp.features.chamferFeatures

        # ============ MAIN FRAME - FRONT RAIL ============
        frontRailSketch = sketches.add(xyPlane)
        frontRailLines = frontRailSketch.sketchCurves.sketchLines

        # Front rail (full width including ears)
        frontRailLines.addTwoPointRectangle(
            adsk.core.Point3D.create(0, 0, 0),
            adsk.core.Point3D.create(rack_width, frame_thickness, 0)
        )

        frontRailProfile = frontRailSketch.profiles.item(0)
        extInput = extrudes.createInput(frontRailProfile, adsk.fusion.FeatureOperations.NewBodyFeatureOperation)
        extInput.setDistanceExtent(False, adsk.core.ValueInput.createByReal(rack_height))
        frontRailExtrude = extrudes.add(extInput)

        # ============ MAIN FRAME - REAR RAIL ============
        rearRailSketch = sketches.add(xyPlane)
        rearRailLines = rearRailSketch.sketchCurves.sketchLines

        # Rear rail (inner width only, no ears)
        rearRailLines.addTwoPointRectangle(
            adsk.core.Point3D.create(ear_width, frame_depth - frame_thickness, 0),
            adsk.core.Point3D.create(rack_width - ear_width, frame_depth, 0)
        )

        rearRailProfile = rearRailSketch.profiles.item(0)
        extInput = extrudes.createInput(rearRailProfile, adsk.fusion.FeatureOperations.JoinFeatureOperation)
        extInput.setDistanceExtent(False, adsk.core.ValueInput.createByReal(rack_height))
        extrudes.add(extInput)

        # ============ SIDE RAILS ============
        # Left side rail
        leftSideSketch = sketches.add(xyPlane)
        leftSideLines = leftSideSketch.sketchCurves.sketchLines
        leftSideLines.addTwoPointRectangle(
            adsk.core.Point3D.create(ear_width, frame_thickness, 0),
            adsk.core.Point3D.create(ear_width + frame_thickness, frame_depth - frame_thickness, 0)
        )
        leftSideProfile = leftSideSketch.profiles.item(0)
        extInput = extrudes.createInput(leftSideProfile, adsk.fusion.FeatureOperations.JoinFeatureOperation)
        extInput.setDistanceExtent(False, adsk.core.ValueInput.createByReal(rack_height))
        extrudes.add(extInput)

        # Right side rail
        rightSideSketch = sketches.add(xyPlane)
        rightSideLines = rightSideSketch.sketchCurves.sketchLines
        rightSideLines.addTwoPointRectangle(
            adsk.core.Point3D.create(rack_width - ear_width - frame_thickness, frame_thickness, 0),
            adsk.core.Point3D.create(rack_width - ear_width, frame_depth - frame_thickness, 0)
        )
        rightSideProfile = rightSideSketch.profiles.item(0)
        extInput = extrudes.createInput(rightSideProfile, adsk.fusion.FeatureOperations.JoinFeatureOperation)
        extInput.setDistanceExtent(False, adsk.core.ValueInput.createByReal(rack_height))
        extrudes.add(extInput)

        # ============ CENTER DIVIDERS (3 dividers for 4 bays) ============
        for i in range(1, num_bays):
            divider_x = ear_width + (bay_width * i) - (frame_thickness / 2)

            dividerSketch = sketches.add(xyPlane)
            dividerLines = dividerSketch.sketchCurves.sketchLines
            dividerLines.addTwoPointRectangle(
                adsk.core.Point3D.create(divider_x, frame_thickness, 0),
                adsk.core.Point3D.create(divider_x + frame_thickness, frame_depth - frame_thickness, 0)
            )
            dividerProfile = dividerSketch.profiles.item(0)
            extInput = extrudes.createInput(dividerProfile, adsk.fusion.FeatureOperations.JoinFeatureOperation)
            extInput.setDistanceExtent(False, adsk.core.ValueInput.createByReal(rack_height))
            extrudes.add(extInput)

        # ============ RACK EAR EXTENSIONS ============
        # The ears extend from the front rail at each corner
        # Left ear reinforcement
        leftEarSketch = sketches.add(xyPlane)
        leftEarLines = leftEarSketch.sketchCurves.sketchLines
        leftEarLines.addTwoPointRectangle(
            adsk.core.Point3D.create(0, 0, 0),
            adsk.core.Point3D.create(ear_width, gusset_size + frame_thickness, 0)
        )
        # This overlaps with front rail, join will merge them

        # Right ear reinforcement
        rightEarSketch = sketches.add(xyPlane)
        rightEarLines = rightEarSketch.sketchCurves.sketchLines
        rightEarLines.addTwoPointRectangle(
            adsk.core.Point3D.create(rack_width - ear_width, 0, 0),
            adsk.core.Point3D.create(rack_width, gusset_size + frame_thickness, 0)
        )

        # ============ CORNER GUSSETS (triangular reinforcements) ============
        # Create gussets at all 4 front corners and center divider connections

        def create_gusset(x_pos, mirror=False):
            """Create a triangular gusset at the given x position"""
            gussetSketch = sketches.add(xyPlane)
            gussetLines = gussetSketch.sketchCurves.sketchLines

            if not mirror:
                # Gusset on left side of vertical member
                p1 = adsk.core.Point3D.create(x_pos, frame_thickness, 0)
                p2 = adsk.core.Point3D.create(x_pos + gusset_size, frame_thickness, 0)
                p3 = adsk.core.Point3D.create(x_pos, frame_thickness + gusset_size, 0)
            else:
                # Gusset on right side of vertical member
                p1 = adsk.core.Point3D.create(x_pos, frame_thickness, 0)
                p2 = adsk.core.Point3D.create(x_pos - gusset_size, frame_thickness, 0)
                p3 = adsk.core.Point3D.create(x_pos, frame_thickness + gusset_size, 0)

            gussetLines.addByTwoPoints(p1, p2)
            gussetLines.addByTwoPoints(p2, p3)
            gussetLines.addByTwoPoints(p3, p1)

            if gussetSketch.profiles.count > 0:
                gussetProfile = gussetSketch.profiles.item(0)
                extInput = extrudes.createInput(gussetProfile, adsk.fusion.FeatureOperations.JoinFeatureOperation)
                extInput.setDistanceExtent(False, adsk.core.ValueInput.createByReal(rack_height))
                extrudes.add(extInput)

        # Front left corner gusset
        create_gusset(ear_width + frame_thickness, mirror=False)

        # Front right corner gusset
        create_gusset(rack_width - ear_width - frame_thickness, mirror=True)

        # Gussets at each center divider (both sides)
        for i in range(1, num_bays):
            divider_x = ear_width + (bay_width * i)
            create_gusset(divider_x - frame_thickness/2, mirror=True)  # Left side of divider
            create_gusset(divider_x + frame_thickness/2, mirror=False) # Right side of divider

        # ============ RACK MOUNTING HOLES ============
        # 2 holes per ear, vertically spaced
        holeFeats = rootComp.features.holeFeatures

        hole_z_positions = [
            rack_height * 0.33,
            rack_height * 0.67
        ]

        for z_pos in hole_z_positions:
            # Create sketch for holes at this height
            constructionPlanes = rootComp.constructionPlanes
            planeInput = constructionPlanes.createInput()
            planeInput.setByOffset(xyPlane, adsk.core.ValueInput.createByReal(z_pos))
            holePlane = constructionPlanes.add(planeInput)

            holeSketch = sketches.add(holePlane)
            holeCircles = holeSketch.sketchCurves.sketchCircles

            # Left ear holes
            holeCircles.addByCenterRadius(
                adsk.core.Point3D.create(ear_width / 2, rack_hole_offset_y, 0),
                rack_hole_diameter / 2
            )

            # Right ear holes
            holeCircles.addByCenterRadius(
                adsk.core.Point3D.create(rack_width - ear_width / 2, rack_hole_offset_y, 0),
                rack_hole_diameter / 2
            )

            # Cut the holes
            for i in range(holeSketch.profiles.count):
                holeProfile = holeSketch.profiles.item(i)
                extInput = extrudes.createInput(holeProfile, adsk.fusion.FeatureOperations.CutFeatureOperation)
                extInput.setDistanceExtent(False, adsk.core.ValueInput.createByReal(frame_thickness + 0.1))
                extrudes.add(extInput)

        # ============ SPLIT PLANE FOR PRINTING ============
        # Add a construction plane at center for easy splitting
        splitPlaneInput = constructionPlanes.createInput()
        splitPlaneInput.setByOffset(yzPlane, adsk.core.ValueInput.createByReal(center_x))
        splitPlane = constructionPlanes.add(splitPlaneInput)
        splitPlane.name = "SPLIT_HERE_FOR_PRINTING"

        # ============ DONE ============
        ui.messageBox(
            '19" Pi Rack Frame Created!\n\n' +
            'Specifications:\n' +
            f'- Width: {rack_width * 10:.1f}mm (19" standard)\n' +
            f'- Height: {rack_height * 10:.1f}mm (1U)\n' +
            f'- Depth: {frame_depth * 10:.1f}mm\n' +
            f'- Bays: {num_bays} (for {num_bays} Raspberry Pis)\n\n' +
            'To split for printing:\n' +
            '1. Find "SPLIT_HERE_FOR_PRINTING" construction plane\n' +
            '2. Use Modify > Split Body\n' +
            '3. Export each half as STL\n\n' +
            'Join halves with M4 bolts through center divider.'
        )

    except:
        if ui:
            ui.messageBox('Failed:\n{}'.format(traceback.format_exc()))
