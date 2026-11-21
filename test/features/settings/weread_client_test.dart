/// 微信读书 Agent API 客户端：请求形状、字段解析、错误透出。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/settings/weread/weread_client.dart';
import 'package:qy_reader/features/settings/weread/weread_models.dart';

void main() {
  test('推荐书籍保留 ID 并读取热门划线和公开书评', () async {
    final calls = <String>[];
    final client = WeReadClient(
      apiKey: 'test',
      post: (url, headers, body) async {
        final api = body['api_name'] as String;
        calls.add(api);
        if (api == '/book/recommend') {
          return {
            'books': [
              {'bookId': 'b1', 'title': '三体'},
            ],
          };
        }
        if (api == '/book/bestbookmarks') {
          return {
            'items': [
              {'markText': '划线原文'},
            ],
          };
        }
        return {
          'reviews': [
            {
              'review': {
                'review': {'content': '好书'},
              },
            },
          ],
        };
      },
    );
    expect((await client.fetchRecommendations()).single.bookId, 'b1');
    expect(await client.fetchPopularHighlights('b1'), ['划线原文']);
    expect(await client.fetchPopularReviews('b1'), ['好书']);
    expect(calls, ['/book/recommend', '/book/bestbookmarks', '/review/list']);
  });

  test('推荐请求与字段解析', () async {
    Map<String, dynamic>? request;
    final client = WeReadClient(
      apiKey: 'test',
      post: (url, headers, body) async {
        request = body;
        return {
          'data': {
            'books': [
              {'title': '三体', 'author': '刘慈欣', 'reason': '科幻佳作'},
            ],
          },
        };
      },
    );
    final books = await client.fetchRecommendations();
    expect(request!['api_name'], '/book/recommend');
    expect(request!['context'], isNotEmpty);
    expect(books.single.title, '三体');
    expect(books.single.reason, '科幻佳作');
  });

  test('书架：请求带 Bearer / api_name / skill_version，回包解析完整', () async {
    final calls =
        <({Uri url, Map<String, String> headers, Map<String, dynamic> body})>[];
    final client = WeReadClient(
      apiKey: 'wrk-test',
      post: (url, headers, body) async {
        calls.add((url: url, headers: headers, body: body));
        return <String, dynamic>{
          'books': <dynamic>[
            <String, dynamic>{
              'bookId': 'b1',
              'title': '三体',
              'author': '刘慈欣',
              'cover': 'https://img/cover.jpg',
              'category': '科幻',
              'readUpdateTime': 1700000000,
              'finishReading': 1,
              'updateTime': 1700000100,
              'readerLink': 'weread://reader/b1',
            },
          ],
          'albums': <dynamic>[
            <String, dynamic>{'albumInfo': <String, dynamic>{}},
          ],
          'mp': <String, dynamic>{'mpId': 'articles'},
          'bookCount': 1,
        };
      },
    );

    final shelf = await client.fetchShelf();
    expect(shelf.books, hasLength(1));
    expect(shelf.albumCount, 1);
    expect(shelf.hasMp, isTrue);
    expect(shelf.bookCount, 1);
    final book = shelf.books.single;
    expect(book.title, '三体');
    expect(book.author, '刘慈欣');
    expect(book.finished, isTrue);
    expect(book.readUpdateTime, 1700000000);
    expect(book.readerLink, 'weread://reader/b1');

    final call = calls.single;
    expect(call.body['api_name'], '/shelf/sync');
    expect(call.body['skill_version'], kWeReadSkillVersion);
    expect(call.headers['Authorization'], 'Bearer wrk-test');
    expect(call.headers['Content-Type'], 'application/json');
  });

  test('阅读进度：progress 是 0..100 整数，时长按秒解析', () async {
    final client = WeReadClient(
      apiKey: 'wrk-test',
      post: (url, headers, body) async => <String, dynamic>{
        'book': <String, dynamic>{
          'progress': 45,
          'updateTime': 1700000001,
          'recordReadingTime': 3661,
          'finishTime': 1700000999,
          'chapterUid': 12,
          'chapterOffset': 30,
        },
      },
    );

    final progress = await client.fetchProgress('b1');
    expect(progress, isNotNull);
    expect(progress!.progressPercent, 45);
    expect(progress.readingSeconds, 3661);
    expect(progress.finishTime, 1700000999);
    expect(progress.chapterUid, 12);
    expect(progress.chapterOffset, 30);
  });

  test('书籍详情：简介 / 出版社 / 封面用于生成占位 EPUB', () async {
    final client = WeReadClient(
      apiKey: 'wrk-test',
      post: (url, headers, body) async {
        expect(body['api_name'], '/book/info');
        expect(body['bookId'], 'b1');
        return <String, dynamic>{
          'bookId': 'b1',
          'title': '三体',
          'author': '刘慈欣',
          'cover': 'https://img/cover.jpg',
          'intro': '给岁月以文明。',
          'category': '科幻',
          'publisher': '重庆出版社',
          'publishTime': '2008-01-01',
          'isbn': '9787536692930',
          'wordCount': 200000,
        };
      },
    );

    final info = await client.fetchBookInfo('b1');
    expect(info.title, '三体');
    expect(info.intro, '给岁月以文明。');
    expect(info.publisher, '重庆出版社');
    expect(info.category, '科幻');
    expect(info.wordCount, 200000);
  });

  test('笔记本概览：分页游标、笔记计数与读完状态', () async {
    final client = WeReadClient(
      apiKey: 'wrk-test',
      post: (url, headers, body) async {
        expect(body['api_name'], '/user/notebooks');
        expect(body['count'], 50);
        expect(body['lastSort'], 99);
        return <String, dynamic>{
          'books': <dynamic>[
            <String, dynamic>{
              'bookId': 'b1',
              'book': <String, dynamic>{
                'title': '三体',
                'author': '刘慈欣',
                'cover': 'c',
              },
              'reviewCount': 2,
              'noteCount': 3,
              'bookmarkCount': 1,
              'readingProgress': 60,
              'markedStatus': 1,
              'sort': 123,
            },
          ],
          'hasMore': 1,
          'totalBookCount': 1,
          'totalNoteCount': 6,
        };
      },
    );

    final page = await client.fetchNotebooksPage(count: 50, lastSort: 99);
    expect(page.hasMore, isTrue);
    expect(page.totalBookCount, 1);
    expect(page.totalNoteCount, 6);
    expect(page.lastSort, 123);
    final notebook = page.notebooks.single;
    expect(notebook.title, '三体');
    expect(notebook.noteCount, 3);
    expect(notebook.reviewCount, 2);
    expect(notebook.totalNotes, 5);
    expect(notebook.readingProgress, 60);
    expect(notebook.finished, isTrue);
  });

  test('划线 + 想法：同 range 合并，无法定位的整本书评单独标记', () async {
    final client = WeReadClient(
      apiKey: 'wrk-test',
      post: (url, headers, body) async {
        switch (body['api_name']) {
          case '/book/bookmarklist':
            return <String, dynamic>{
              'chapters': <dynamic>[
                <String, dynamic>{
                  'chapterUid': 7,
                  'chapterIdx': 0,
                  'title': '第一章',
                },
              ],
              'updated': <dynamic>[
                <String, dynamic>{
                  'bookmarkId': 'm1',
                  'chapterUid': 7,
                  'markText': '山川湖海',
                  'range': '10-14',
                  'colorStyle': 1,
                  'createTime': 1700000000,
                },
              ],
            };
          case '/review/list/mine':
            expect(body['bookid'], 'b1');
            return <String, dynamic>{
              'reviews': <dynamic>[
                <String, dynamic>{
                  'review': <String, dynamic>{
                    'reviewId': 'r1',
                    'content': '写得好',
                    'abstract': '山川湖海',
                    'range': '10-14',
                    'chapterUid': 7,
                    'chapterIdx': 0,
                    'createTime': 1700000001,
                    'updateTime': 1700000010,
                  },
                },
                <String, dynamic>{
                  'review': <String, dynamic>{
                    'reviewId': 'r2',
                    'content': '整本书评',
                    'createTime': 1700000002,
                  },
                },
              ],
            };
        }
        throw StateError('unexpected api: ${body['api_name']}');
      },
    );

    final notes = await client.fetchNotes('b1');
    expect(notes, hasLength(2));
    final marked = notes.firstWhere((note) => note.id == 'm1');
    expect(marked.quote, '山川湖海');
    expect(marked.thought, '写得好');
    expect(marked.chapterIdx, 0);
    expect(marked.chapterName, '第一章');
    expect(marked.editedAt, 1700000010);
    final review = notes.firstWhere((note) => note.id == 'r2');
    expect(review.wholeBookReview, isTrue);
    expect(review.thought, '整本书评');
  });

  test('划线接口失败但想法接口成功时，仍返回想法内容', () async {
    final client = WeReadClient(
      apiKey: 'wrk-test',
      post: (url, headers, body) async {
        if (body['api_name'] == '/book/bookmarklist') {
          throw const WeReadApiException('bookmarklist 暂不可用');
        }
        return <String, dynamic>{
          'reviews': <dynamic>[
            <String, dynamic>{
              'review': <String, dynamic>{
                'reviewId': 'r1',
                'content': '这段写得真好',
                'abstract': '山川湖海',
                'range': '10-14',
                'chapterUid': 7,
                'createTime': 1700000000,
              },
            },
          ],
        };
      },
    );

    final notes = await client.fetchNotes('b1');
    expect(notes, hasLength(1));
    expect(notes.single.quote, '山川湖海');
    expect(notes.single.thought, '这段写得真好');
  });

  test('errcode 非 0：抛可读异常', () async {
    final client = WeReadClient(
      apiKey: 'bad',
      post: (url, headers, body) async => <String, dynamic>{
        'errcode': 10001,
        'errmsg': 'API Key 无效',
      },
    );

    await expectLater(
      client.fetchShelf(),
      throwsA(
        isA<WeReadApiException>().having(
          (e) => e.message,
          'message',
          contains('API Key 无效'),
        ),
      ),
    );
  });

  test('upgrade_info 不阻断成功数据，仍通知调用方', () async {
    String? notice;
    final client = WeReadClient(
      apiKey: 'wrk-test',
      onUpgrade: (message) => notice = message,
      post: (url, headers, body) async => <String, dynamic>{
        'upgrade_info': <String, dynamic>{'message': '请升级'},
        'books': <dynamic>[
          <String, dynamic>{'bookId': 'b1', 'title': '三体'},
        ],
      },
    );
    final shelf = await client.fetchShelf();
    expect(shelf.books.single.title, '三体');
    expect(notice, '请升级');
    expect(kWeReadSkillVersion, '1.0.6');
  });

  test('包含升级通知的错误仍然报告真实接口错误', () async {
    final client = WeReadClient(
      apiKey: 'bad',
      post: (url, headers, body) async => {
        'upgrade_info': {'message': '请升级'},
        'errcode': 10001,
        'errmsg': 'API Key 无效',
      },
    );
    await expectLater(
      client.fetchShelf(),
      throwsA(
        isA<WeReadApiException>().having(
          (e) => e.message,
          'message',
          contains('API Key 无效'),
        ),
      ),
    );
  });
}
