import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/shelf/widgets/book_file_share.dart';

Book book(String id, String title) => Book(
  id: id,
  title: title,
  format: BookFormat.epub,
  filePath: '/books/$id.epub',
  fileSha256: id,
  fileSize: 1,
  addedAt: 0,
  updatedAt: 0,
  hlc: '',
  deviceId: 'a',
);
void main() {
  test('导出文件名过滤特殊字符并避免同名', () {
    expect(bookExportName('a/b:*', '.epub'), 'a_b__.epub');
    expect(bookExportName('CON', '.txt'), '_CON.txt');
    expect(uniqueBookExportNames([book('a', '书'), book('b', '书')]), [
      '书.epub',
      '书 (2).epub',
    ]);
  });
  test('多本书打包保留文件名和原始内容', () async {
    final dir = await Directory.systemTemp.createTemp('qy_export_test_');
    addTearDown(() => dir.delete(recursive: true));
    final first = await File('${dir.path}/a').writeAsBytes([1, 2, 3]);
    final second = await File('${dir.path}/b').writeAsBytes([4, 5]);
    final zip = await archiveBookFiles(
      [first.path, second.path],
      ['一本.epub', '二本.txt'],
    );
    final archive = ZipDecoder().decodeBytes(zip);
    expect(archive.files.map((f) => f.name), ['一本.epub', '二本.txt']);
    expect(archive.files.first.content, [1, 2, 3]);
    expect(archive.files.last.content, [4, 5]);
  });
}
