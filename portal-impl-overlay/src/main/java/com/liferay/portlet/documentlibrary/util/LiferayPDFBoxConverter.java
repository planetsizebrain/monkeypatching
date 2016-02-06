/**
 * Copyright (c) 2000-2013 Liferay, Inc. All rights reserved.
 *
 * This library is free software; you can redistribute it and/or modify it under
 * the terms of the GNU Lesser General Public License as published by the Free
 * Software Foundation; either version 2.1 of the License, or (at your option)
 * any later version.
 *
 * This library is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
 * details.
 */

package com.liferay.portlet.documentlibrary.util;

import com.liferay.portal.image.ImageToolImpl;
import com.liferay.portal.kernel.image.ImageTool;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDDocumentCatalog;
import org.apache.pdfbox.pdmodel.PDPageTree;
import org.apache.pdfbox.rendering.ImageType;
import org.apache.pdfbox.rendering.PDFRenderer;

import javax.imageio.ImageIO;
import java.awt.image.RenderedImage;
import java.io.File;

/**
 * @author Juan Gonzalez
 */
public class LiferayPDFBoxConverter {

	public LiferayPDFBoxConverter(
			File inputFile, File thumbnailFile, File[] previewFiles,
			String extension, String thumbnailExtension, int dpi, int height,
			int width, boolean generatePreview, boolean generateThumbnail) {

		_inputFile = inputFile;
		_thumbnailFile = thumbnailFile;
		_previewFiles = previewFiles;
		_extension = extension;
		_thumbnailExtension = thumbnailExtension;
		_dpi = dpi;
		_height = height;
		_width = width;
		_generatePreview = generatePreview;
		_generateThumbnail = generateThumbnail;
	}

	public void generateImagesPB() throws Exception {
		PDDocument pdDocument = null;

		try {
			pdDocument = PDDocument.load(_inputFile);

			PDDocumentCatalog pdDocumentCatalog =
				pdDocument.getDocumentCatalog();

			PDFRenderer pdfRenderer = new PDFRenderer(pdDocument);

			PDPageTree pdPages = pdDocumentCatalog.getPages();

			for (int i = 0; i < pdPages.getCount(); i++) {
				if (_generateThumbnail && (i == 0)) {
					_generateImagesPB(
						pdfRenderer, i, _thumbnailFile, _thumbnailExtension);
				}

				if (!_generatePreview) {
					break;
				}

				_generateImagesPB(pdfRenderer, i, _previewFiles[i], _extension);
			}
		}
		finally {
			if (pdDocument != null) {
				pdDocument.close();
			}
		}
	}

	private void _generateImagesPB(
			PDFRenderer pdfRenderer, int index, File outputFile, String extension)
		throws Exception {

		RenderedImage renderedImage = pdfRenderer.renderImageWithDPI(index, _dpi, ImageType.RGB);

		ImageTool imageTool = ImageToolImpl.getInstance();

		if (_height != 0) {
			renderedImage = imageTool.scale(renderedImage, _width, _height);
		}
		else {
			renderedImage = imageTool.scale(renderedImage, _width);
		}

		outputFile.createNewFile();

		ImageIO.write(renderedImage, extension, outputFile);
	}

	private int _dpi;
	private String _extension;
	private boolean _generatePreview;
	private boolean _generateThumbnail;
	private int _height;
	private File _inputFile;
	private File[] _previewFiles;
	private String _thumbnailExtension;
	private File _thumbnailFile;
	private int _width;

}