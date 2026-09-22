package firestore

import (
	"context"
	"fmt"
	"regexp"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
)

const collection = "restrictions"

type Restriction struct {
	ID          string  `json:"id"`
	Lat         float64 `json:"lat"`
	Lng         float64 `json:"lng"`
	Type        string  `json:"type"`
	Value       float64 `json:"value"`
	RoadName    string  `json:"roadName,omitempty"`
	ConfirmedBy int     `json:"confirmedBy"`
}

type CreateInput struct {
	Lat      float64 `json:"lat"`
	Lng      float64 `json:"lng"`
	Type     string  `json:"type"`
	Value    float64 `json:"value"`
	RoadName string  `json:"roadName,omitempty"`
	UID      string  `json:"uid"`
}

func ListInBounds(ctx context.Context, client *firestore.Client, minLat, maxLat, minLng, maxLng float64) ([]Restriction, error) {
	iter := client.Collection(collection).
		Where("lat", ">=", minLat).
		Where("lat", "<=", maxLat).
		Documents(ctx)
	defer iter.Stop()

	var results []Restriction
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("iterate: %w", err)
		}
		r := fromDoc(doc)
		if r.Lng >= minLng && r.Lng <= maxLng {
			results = append(results, r)
		}
	}
	return results, nil
}

func Create(ctx context.Context, client *firestore.Client, in CreateInput) (string, error) {
	ref, _, err := client.Collection(collection).Add(ctx, map[string]any{
		"lat":         in.Lat,
		"lng":         in.Lng,
		"type":        in.Type,
		"value":       in.Value,
		"roadName":    in.RoadName,
		"createdByUid": in.UID,
		"confirmedBy": 0,
		"reportedBy":  0,
		"source":      "user",
	})
	if err != nil {
		return "", fmt.Errorf("add: %w", err)
	}
	return ref.ID, nil
}

var installRe = regexp.MustCompile(`^[0-9a-f]{32}$`)

// Dono é quem CONTA como um votante: o aparelho quando ele se identificou, o
// uid quando não. O uid do Firebase não serve sozinho porque a sessão do Auth
// se perde em alguns aparelhos e nasce um uid novo por abertura — o mesmo
// motorista atravessaria o piso de 3 confirmações sozinho.
func Dono(install, uid string) string {
	if installRe.MatchString(install) {
		return install
	}
	return uid
}

// VotoLido é um voto já lido da subcoleção, pra [ContarDonos].
type VotoLido struct{ UID, Install, Action string }

// ContarDonos conta APARELHOS distintos por ação, com o voto que está sendo
// dado agora sobrescrevendo o que este uid tinha antes. Pura, pra teste.
//
// Entre votos ANTIGOS do mesmo aparelho (dois uids do mesmo motorista, opiniões
// diferentes, e o voto atual vindo de um terceiro uid) o desempate é
// arbitrário: é a mesma pessoa, e o voto atual decide na hora em que ela votar.
func ContarDonos(vs []VotoLido, uid, install, action string) (confirm, report int) {
	porDono := make(map[string]string, len(vs)+1)
	for _, v := range vs {
		porDono[Dono(v.Install, v.UID)] = v.Action
	}
	porDono[Dono(install, uid)] = action
	for _, a := range porDono {
		if a == "confirm" {
			confirm++
		} else {
			report++
		}
	}
	return confirm, report
}

// Vote registra um voto "confirm"/"report" e RECALCULA os contadores contando
// aparelhos distintos.
//
// Era `Increment(±1)` por uid. Contador por delta não dá pra desduplicar depois
// (não há como saber quais incrementos vieram do mesmo celular), então a forma
// passou a ser a mesma que o radar já usa: recontar do zero. Estado derivado
// que se auto-corrige não acumula erro de contagem, e com dezenas de motoristas
// são poucas leituras.
//
// ⚠️ Transação do Firestore exige TODAS as leituras antes de qualquer escrita:
// por isso a subcoleção é lida primeiro e só depois vêm o Set e o Update.
func Vote(ctx context.Context, client *firestore.Client, id, uid, install, action string) error {
	restrictionRef := client.Collection(collection).Doc(id)
	voteRef := restrictionRef.Collection("votes").Doc(uid)

	return client.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		votos, err := lerVotos(tx, restrictionRef)
		if err != nil {
			return fmt.Errorf("ler votos: %w", err)
		}
		confirm, report := ContarDonos(votos, uid, install, action)

		if err := tx.Set(voteRef, map[string]any{
			"action": action, "install": install, "at": time.Now(),
		}); err != nil {
			return err
		}
		return tx.Update(restrictionRef, []firestore.Update{
			{Path: "confirmedBy", Value: confirm},
			{Path: "reportedBy", Value: report},
		})
	})
}

// lerVotos traz a subcoleção inteira DENTRO da transação — é o que garante que
// a recontagem enxerga o mesmo conjunto que está sendo atualizado.
func lerVotos(tx *firestore.Transaction,
	restrictionRef *firestore.DocumentRef) ([]VotoLido, error) {
	it := tx.Documents(restrictionRef.Collection("votes"))
	defer it.Stop()
	var out []VotoLido
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			return out, nil
		}
		if err != nil {
			return nil, err
		}
		d := doc.Data()
		action, _ := d["action"].(string)
		install, _ := d["install"].(string)
		out = append(out, VotoLido{
			UID: doc.Ref.ID, Install: install, Action: action,
		})
	}
}

func fromDoc(doc *firestore.DocumentSnapshot) Restriction {
	d := doc.Data()
	r := Restriction{ID: doc.Ref.ID}
	if v, ok := d["lat"].(float64); ok {
		r.Lat = v
	}
	if v, ok := d["lng"].(float64); ok {
		r.Lng = v
	}
	if v, ok := d["type"].(string); ok {
		r.Type = v
	}
	if v, ok := d["value"].(float64); ok {
		r.Value = v
	}
	if v, ok := d["roadName"].(string); ok {
		r.RoadName = v
	}
	if v, ok := d["confirmedBy"].(int64); ok {
		r.ConfirmedBy = int(v)
	}
	return r
}
